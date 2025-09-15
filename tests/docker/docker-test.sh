#!/bin/bash
#
# Pi Gateway - Docker-based Integration Testing
# Alternative to QEMU for cross-platform testing
#
# DUAL-MODE ARCHITECTURE:
# - Simple Mode (default): Lightweight container with mock systemctl
# - Systemd Mode: Full systemd support for advanced service testing
#
# Usage:
#   USE_SIMPLE_MODE=true  ./docker-test.sh run  (default, fast)
#   USE_SIMPLE_MODE=false ./docker-test.sh run  (systemd mode)
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PI_GATEWAY_ROOT="$SCRIPT_DIR/../.."
readonly CONTAINER_NAME="pi-gateway-test"
readonly IMAGE_NAME="pi-gateway:test"
readonly USE_SIMPLE_MODE="${USE_SIMPLE_MODE:-true}"  # Use simple mode by default

# Logging functions
success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

error() {
    echo -e "  ${RED}✗${NC} $1"
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Pi Gateway - Docker Integration Tests     ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

check_docker() {
    info "Checking Docker installation..."

    if ! command -v docker >/dev/null 2>&1; then
        error "Docker not found. Please install Docker first."
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon not running. Please start Docker."
        exit 1
    fi

    success "Docker is available and running"
}

build_test_image() {
    if [[ "$USE_SIMPLE_MODE" == "true" ]]; then
        info "Building Pi Gateway test image (simple mode)..."
        local dockerfile="tests/docker/Dockerfile.simple"
    else
        info "Building Pi Gateway test image (systemd mode)..."
        local dockerfile="tests/docker/Dockerfile"
    fi

    cd "$PI_GATEWAY_ROOT"

    # Try to build ARM64 image first, then fall back to native
    local build_success=false

    # Try ARM64 build with buildx if available
    if docker buildx version >/dev/null 2>&1; then
        info "Attempting ARM64 build with buildx..."
        if docker buildx build \
            --platform linux/arm64 \
            -t "$IMAGE_NAME" \
            -f "$dockerfile" \
            . 2>/dev/null; then
            build_success=true
        else
            warning "ARM64 build failed, trying native build..."
        fi
    fi

    # Fall back to native build if ARM64 failed
    if [[ "$build_success" == "false" ]]; then
        info "Building with native platform..."
        docker build -t "$IMAGE_NAME" -f "$dockerfile" .
    fi

    success "Test image built successfully"
}

start_test_container() {
    info "Starting test container..."

    # Stop existing container if running
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true

    if [[ "$USE_SIMPLE_MODE" == "true" ]]; then
        # Simple mode - just SSH daemon
        docker run -d \
            --name "$CONTAINER_NAME" \
            -p 2222:22 \
            "$IMAGE_NAME"

        # Wait for SSH to be ready
        info "Waiting for SSH service to start..."
        sleep 5

        # Test SSH connectivity
        if docker exec "$CONTAINER_NAME" pgrep sshd >/dev/null 2>&1; then
            success "SSH service is running"
        else
            info "Starting SSH service manually..."
            docker exec "$CONTAINER_NAME" /usr/sbin/sshd -D &
            sleep 2
        fi
    else
        # Systemd mode - full systemd support
        docker run -d \
            --name "$CONTAINER_NAME" \
            --privileged \
            --tmpfs /run \
            --tmpfs /run/lock \
            -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
            -p 2222:22 \
            "$IMAGE_NAME" \
            /lib/systemd/systemd

        # Wait for container to be ready and systemd to initialize
        info "Waiting for systemd to initialize..."
        sleep 10

        # Wait for systemd to be ready
        local max_wait=30
        local count=0
        while ! docker exec "$CONTAINER_NAME" systemctl is-system-running --wait >/dev/null 2>&1; do
            if [[ $count -ge $max_wait ]]; then
                warning "Systemd initialization timeout, proceeding anyway..."
                break
            fi
            sleep 2
            ((count += 2))
        done

        # Start SSH service
        info "Starting SSH service..."
        docker exec "$CONTAINER_NAME" systemctl start ssh.service || {
            warning "SSH service start failed, trying manual start..."
            docker exec "$CONTAINER_NAME" /usr/sbin/sshd -D &
        }
    fi

    success "Test container started: $CONTAINER_NAME"
}

run_script_in_container() {
    local script_name="$1"
    local script_path="scripts/$script_name"

    info "Running $script_name in container..."

    # Ensure script is executable
    docker exec "$CONTAINER_NAME" chmod +x "/home/pi/pi-gateway/$script_path"

    # Run script as pi user with sudo
    docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && sudo ./$script_path"
}

run_check_requirements_test() {
    echo
    info "Testing check-requirements.sh..."

    if run_script_in_container "check-requirements.sh"; then
        success "check-requirements.sh completed"
    else
        error "check-requirements.sh failed"
        return 1
    fi
}

run_install_dependencies_test() {
    echo
    info "Testing install-dependencies.sh..."

    if run_script_in_container "install-dependencies.sh"; then
        success "install-dependencies.sh completed"
    else
        warning "install-dependencies.sh completed with warnings"
    fi

    # Verify key packages were installed
    info "Verifying package installations..."

    local packages=("curl" "wget" "git" "ufw" "fail2ban")
    for package in "${packages[@]}"; do
        if docker exec "$CONTAINER_NAME" dpkg -l "$package" >/dev/null 2>&1; then
            success "$package installed"
        else
            error "$package not found"
        fi
    done
}

run_system_hardening_test() {
    echo
    info "Testing system-hardening.sh..."

    if run_script_in_container "system-hardening.sh"; then
        success "system-hardening.sh completed"
    else
        warning "system-hardening.sh completed with warnings"
    fi

    # Verify hardening was applied
    info "Verifying system hardening..."

    # Check if SSH service is still running
    if docker exec "$CONTAINER_NAME" systemctl is-active ssh >/dev/null 2>&1; then
        success "SSH service still active after hardening"
    else
        warning "SSH service not active"
    fi
}

run_service_tests() {
    echo
    info "Testing service configurations..."

    # Test SSH service
    if docker exec "$CONTAINER_NAME" systemctl is-enabled ssh >/dev/null 2>&1; then
        success "SSH service is enabled"
    else
        error "SSH service not enabled"
    fi

    # Test fail2ban service (if installed)
    if docker exec "$CONTAINER_NAME" systemctl is-enabled fail2ban >/dev/null 2>&1; then
        success "fail2ban service is enabled"
    else
        info "fail2ban service not enabled (may be expected)"
    fi
}

run_integration_tests() {
    print_header

    check_docker
    build_test_image
    start_test_container

    local test_results=0

    run_check_requirements_test || ((test_results++))
    run_install_dependencies_test || ((test_results++))
    run_system_hardening_test || ((test_results++))
    run_service_tests || ((test_results++))

    echo
    if [[ $test_results -eq 0 ]]; then
        success "All integration tests passed!"
    else
        warning "$test_results test(s) had issues"
    fi

    return $test_results
}

cleanup_containers() {
    info "Cleaning up test containers..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    success "Cleanup completed"
}

show_container_logs() {
    echo
    info "Container logs:"
    docker logs "$CONTAINER_NAME" 2>/dev/null || echo "No logs available"
}

# Handle different commands
case "${1:-run}" in
    "run")
        run_integration_tests
        ;;
    "build")
        check_docker
        build_test_image
        ;;
    "start")
        check_docker
        start_test_container
        ;;
    "cleanup")
        cleanup_containers
        ;;
    "logs")
        show_container_logs
        ;;
    "shell")
        info "Starting shell in test container..."
        docker exec -it "$CONTAINER_NAME" /bin/bash
        ;;
    *)
        echo "Usage: $0 [run|build|start|cleanup|logs|shell]"
        echo
        echo "Commands:"
        echo "  run     - Run complete integration test suite (default)"
        echo "  build   - Build test container image only"
        echo "  start   - Start test container only"
        echo "  cleanup - Stop and remove test containers"
        echo "  logs    - Show container logs"
        echo "  shell   - Open shell in running container"
        echo
        echo "Environment Variables:"
        echo "  USE_SIMPLE_MODE=true  - Use simplified container without systemd (default)"
        echo "  USE_SIMPLE_MODE=false - Use full systemd container"
        echo
        echo "Examples:"
        echo "  $0 run                    # Run tests in simple mode"
        echo "  USE_SIMPLE_MODE=false $0 run  # Run tests in systemd mode"
        exit 1
        ;;
esac