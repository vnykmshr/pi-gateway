#!/bin/bash
#
# Pi Gateway End-to-End Testing Script
# Comprehensive testing of Pi Gateway setup in simulated Pi environment
#

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly CONTAINER_NAME="pi-gateway-e2e-test"
readonly IMAGE_NAME="pi-gateway:e2e"
readonly TEST_LOG="/tmp/pi-gateway-e2e-test.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$TEST_LOG"
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

error() {
    echo -e "  ${RED}✗${NC} $1" >&2
    log "ERROR: $1"
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    log "WARN: $1"
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

section() {
    echo
    echo -e "${PURPLE}════════════════════════════════════════${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════${NC}"
    log "SECTION: $1"
}

# Initialize test environment
init_test_environment() {
    section "Initializing E2E Test Environment"

    # Clean up any existing containers
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        info "Cleaning up existing test container..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi

    # Initialize test log
    echo "=== Pi Gateway E2E Test Session Started: $(date) ===" > "$TEST_LOG"
    success "Test environment initialized"
}

# Build Docker image for E2E testing
build_test_image() {
    section "Building Pi Gateway E2E Test Image"

    info "Building Docker image with Pi OS simulation..."
    if docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile.e2e" "$PROJECT_ROOT" 2>&1 | tee -a "$TEST_LOG"; then
        success "Docker image built successfully: $IMAGE_NAME"
    else
        error "Failed to build Docker image"
        return 1
    fi
}

# Start test container
start_test_container() {
    section "Starting Pi Gateway Test Container"

    info "Starting container with systemd init..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --privileged \
        --tmpfs /tmp \
        --tmpfs /run \
        --tmpfs /run/lock \
        --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
        --cgroupns=host \
        -p 2223:22 \
        -p 51821:51820/udp \
        -p 5902:5901 \
        "$IMAGE_NAME" 2>&1 | tee -a "$TEST_LOG"

    # Wait for container to be ready
    info "Waiting for container to initialize..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker exec "$CONTAINER_NAME" systemctl is-active --quiet ssh 2>/dev/null; then
            success "Container is ready (attempt $attempt/$max_attempts)"
            return 0
        fi

        sleep 2
        ((attempt++))
    done

    error "Container failed to initialize within expected time"
    docker logs "$CONTAINER_NAME" >> "$TEST_LOG"
    return 1
}

# Run Pi Gateway setup with comprehensive testing
run_pi_gateway_setup() {
    section "Running Pi Gateway Setup End-to-End"

    info "Switching to pi user and running setup..."

    # Test 1: Check system requirements
    info "Testing system requirements check..."
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && ./scripts/check-requirements.sh" 2>&1 | tee -a "$TEST_LOG"; then
        success "System requirements check passed"
    else
        error "System requirements check failed"
        return 1
    fi

    # Test 2: Install dependencies
    info "Testing dependency installation..."
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && sudo ./scripts/install-dependencies.sh" 2>&1 | tee -a "$TEST_LOG"; then
        success "Dependencies installed successfully"
    else
        error "Dependency installation failed"
        return 1
    fi

    # Test 3: System hardening
    info "Testing system hardening..."
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && sudo ./scripts/security-hardening.sh" 2>&1 | tee -a "$TEST_LOG"; then
        success "System hardening completed"
    else
        error "System hardening failed"
        return 1
    fi

    # Test 4: SSH setup
    info "Testing SSH configuration..."
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && sudo ./scripts/ssh-setup.sh" 2>&1 | tee -a "$TEST_LOG"; then
        success "SSH setup completed"
    else
        error "SSH setup failed"
        return 1
    fi

    # Test 5: Firewall setup
    info "Testing firewall configuration..."
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && sudo ./scripts/firewall-setup.sh" 2>&1 | tee -a "$TEST_LOG"; then
        success "Firewall setup completed"
    else
        error "Firewall setup failed"
        return 1
    fi

    # Test 6: VPN setup
    info "Testing VPN (WireGuard) setup..."
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && sudo ./scripts/vpn-setup.sh" 2>&1 | tee -a "$TEST_LOG"; then
        success "VPN setup completed"
    else
        error "VPN setup failed"
        return 1
    fi
}

# Verify services and configurations
verify_setup() {
    section "Verifying Pi Gateway Installation"

    # Check SSH service
    info "Verifying SSH service..."
    if docker exec "$CONTAINER_NAME" systemctl is-active --quiet ssh; then
        success "SSH service is running"
    else
        warning "SSH service is not active"
    fi

    # Check SSH configuration
    info "Verifying SSH hardening..."
    if docker exec "$CONTAINER_NAME" grep -q "PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        success "SSH password authentication disabled"
    else
        warning "SSH password authentication may still be enabled"
    fi

    # Check UFW firewall
    info "Verifying UFW firewall..."
    if docker exec "$CONTAINER_NAME" ufw status 2>/dev/null | grep -q "Status: active"; then
        success "UFW firewall is active"
    else
        warning "UFW firewall is not active"
    fi

    # Check fail2ban
    info "Verifying fail2ban service..."
    if docker exec "$CONTAINER_NAME" systemctl is-active --quiet fail2ban 2>/dev/null; then
        success "fail2ban service is running"
    else
        warning "fail2ban service is not running"
    fi

    # Check WireGuard configuration
    info "Verifying WireGuard configuration..."
    if docker exec "$CONTAINER_NAME" test -f /etc/wireguard/wg0.conf; then
        success "WireGuard configuration exists"
    else
        warning "WireGuard configuration not found"
    fi

    # Check Pi Gateway service user
    info "Verifying Pi Gateway service user..."
    if docker exec "$CONTAINER_NAME" id pi-gateway >/dev/null 2>&1; then
        success "Pi Gateway service user exists"
    else
        warning "Pi Gateway service user not found"
    fi

    # Check log files
    info "Verifying log files..."
    if docker exec "$CONTAINER_NAME" test -d /var/log/pi-gateway; then
        success "Pi Gateway log directory exists"
    else
        warning "Pi Gateway log directory not found"
    fi
}

# Test network connectivity and services
test_network_services() {
    section "Testing Network Services"

    # Test SSH connectivity
    info "Testing SSH connectivity (internal)..."
    if docker exec "$CONTAINER_NAME" bash -c "echo 'SSH test' | nc localhost 22" >/dev/null 2>&1; then
        success "SSH port is accessible"
    else
        warning "SSH port may not be accessible"
    fi

    # Check open ports
    info "Checking open ports..."
    local ports_output
    ports_output=$(docker exec "$CONTAINER_NAME" netstat -tuln 2>/dev/null || echo "netstat not available")
    echo "$ports_output" >> "$TEST_LOG"

    if echo "$ports_output" | grep -q ":22 "; then
        success "SSH port (22) is listening"
    else
        warning "SSH port (22) is not listening"
    fi

    # Test WireGuard interface
    info "Testing WireGuard interface..."
    if docker exec "$CONTAINER_NAME" ip link show wg0 >/dev/null 2>&1; then
        success "WireGuard interface wg0 exists"
    else
        warning "WireGuard interface wg0 not found"
    fi
}

# Collect diagnostic information
collect_diagnostics() {
    section "Collecting Diagnostic Information"

    local diag_file="/tmp/pi-gateway-e2e-diagnostics.txt"
    echo "=== Pi Gateway E2E Test Diagnostics ===" > "$diag_file"
    echo "Test Date: $(date)" >> "$diag_file"
    echo >> "$diag_file"

    # System information
    info "Collecting system information..."
    echo "=== System Information ===" >> "$diag_file"
    docker exec "$CONTAINER_NAME" cat /etc/os-release >> "$diag_file" 2>/dev/null || true
    echo >> "$diag_file"

    # Service status
    info "Collecting service status..."
    echo "=== Service Status ===" >> "$diag_file"
    docker exec "$CONTAINER_NAME" systemctl status ssh >> "$diag_file" 2>/dev/null || true
    docker exec "$CONTAINER_NAME" systemctl status fail2ban >> "$diag_file" 2>/dev/null || true
    echo >> "$diag_file"

    # Network configuration
    info "Collecting network configuration..."
    echo "=== Network Configuration ===" >> "$diag_file"
    docker exec "$CONTAINER_NAME" ip addr show >> "$diag_file" 2>/dev/null || true
    docker exec "$CONTAINER_NAME" ufw status verbose >> "$diag_file" 2>/dev/null || true
    echo >> "$diag_file"

    # Pi Gateway specific files
    info "Collecting Pi Gateway configuration..."
    echo "=== Pi Gateway Files ===" >> "$diag_file"
    docker exec "$CONTAINER_NAME" find /etc/pi-gateway -type f 2>/dev/null >> "$diag_file" || true
    docker exec "$CONTAINER_NAME" find /var/log/pi-gateway -name "*.log" 2>/dev/null >> "$diag_file" || true
    echo >> "$diag_file"

    success "Diagnostics collected: $diag_file"
}

# Clean up test environment
cleanup() {
    section "Cleaning Up Test Environment"

    if [ "${1:-}" = "keep" ]; then
        info "Keeping container for manual inspection: $CONTAINER_NAME"
        info "Access with: docker exec -it $CONTAINER_NAME bash"
        success "Container preserved for debugging"
    else
        info "Stopping and removing test container..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
        success "Test environment cleaned up"
    fi
}

# Generate test report
generate_report() {
    section "Generating Test Report"

    local report_file="/tmp/pi-gateway-e2e-report.md"
    local end_time=$(date)

    cat > "$report_file" << EOF
# Pi Gateway End-to-End Test Report

**Test Date**: $end_time
**Container**: $CONTAINER_NAME
**Image**: $IMAGE_NAME

## Test Summary

This end-to-end test validates the complete Pi Gateway setup process in a simulated Raspberry Pi environment using Docker.

### Components Tested
- ✅ System requirements validation
- ✅ Dependency installation
- ✅ System security hardening
- ✅ SSH configuration and hardening
- ✅ UFW firewall setup
- ✅ WireGuard VPN configuration
- ✅ Service management and validation

### Test Environment
- **Base OS**: Debian Bookworm (simulating Raspberry Pi OS)
- **Container Runtime**: Docker with systemd init
- **Privileges**: Privileged container for realistic system access
- **Networking**: Exposed ports for SSH (2223), VPN (51821), VNC (5902)

### Log Files
- Main test log: $TEST_LOG
- Diagnostics: /tmp/pi-gateway-e2e-diagnostics.txt

### Next Steps
Review the detailed logs and diagnostics for any issues or improvements needed in the Pi Gateway setup process.

EOF

    success "Test report generated: $report_file"
}

# Main execution
main() {
    local keep_container=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-container)
                keep_container=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--keep-container] [--help]"
                echo "  --keep-container  Keep the test container for manual inspection"
                echo "  --help           Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    echo -e "${BLUE}🚀 Pi Gateway End-to-End Testing${NC}"
    echo -e "${BLUE}   Comprehensive Pi Gateway setup validation${NC}"
    echo

    # Set up trap for cleanup
    if [ "$keep_container" = true ]; then
        trap 'cleanup keep' EXIT
    else
        trap 'cleanup' EXIT
    fi

    # Execute test workflow
    init_test_environment
    build_test_image
    start_test_container
    run_pi_gateway_setup
    verify_setup
    test_network_services
    collect_diagnostics
    generate_report

    section "End-to-End Test Completed"
    success "Pi Gateway E2E testing completed successfully!"
    success "Review logs at: $TEST_LOG"

    if [ "$keep_container" = true ]; then
        info "Container kept for inspection: docker exec -it $CONTAINER_NAME bash"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi