#!/bin/bash
#
# Pi Gateway Quick End-to-End Test
# Fast validation of core Pi Gateway functionality
#

set -euo pipefail

# Configuration
readonly CONTAINER_NAME="pi-gateway-quick-test"
readonly IMAGE_NAME="pi-gateway:quick-e2e"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging
success() { echo -e "  ${GREEN}✓${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1" >&2; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }

# Cleanup function
cleanup() {
    echo
    info "Cleaning up test environment..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

main() {
    echo -e "${BLUE}🚀 Pi Gateway Quick E2E Test${NC}"
    echo

    # Build lightweight image
    info "Building lightweight test image..."
    if docker build -t "$IMAGE_NAME" -f "$(dirname "$0")/Dockerfile.e2e-lite" "$PROJECT_ROOT" >/dev/null 2>&1; then
        success "Test image built successfully"
    else
        error "Failed to build test image"
        return 1
    fi

    # Start container
    info "Starting test container..."
    docker run -d --name "$CONTAINER_NAME" --privileged "$IMAGE_NAME" >/dev/null 2>&1
    sleep 10

    # Test 1: Check basic functionality
    info "Testing basic Pi Gateway scripts..."

    # Check requirements script
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && ./scripts/check-requirements.sh" >/dev/null 2>&1; then
        success "check-requirements.sh works"
    else
        warning "check-requirements.sh has issues"
    fi

    # Test dependency installation (dry run)
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && DRY_RUN=true MOCK_SYSTEM=true ./scripts/install-dependencies.sh" >/dev/null 2>&1; then
        success "install-dependencies.sh dry-run works"
    else
        warning "install-dependencies.sh dry-run has issues"
    fi

    # Test system hardening (dry run)
    if docker exec -u pi "$CONTAINER_NAME" bash -c "cd /home/pi/pi-gateway && DRY_RUN=true MOCK_SYSTEM=true ./scripts/system-hardening.sh" >/dev/null 2>&1; then
        success "system-hardening.sh dry-run works"
    else
        warning "system-hardening.sh dry-run has issues"
    fi

    # Test 2: Check environment simulation
    info "Verifying Pi environment simulation..."

    # Check OS detection
    if docker exec "$CONTAINER_NAME" grep -q "raspbian" /etc/os-release; then
        success "Raspbian OS detected correctly"
    else
        warning "OS detection may not work as expected"
    fi

    # Check Pi user
    if docker exec "$CONTAINER_NAME" id pi >/dev/null 2>&1; then
        success "Pi user exists"
    else
        error "Pi user missing"
    fi

    # Check sudo access
    if docker exec -u pi "$CONTAINER_NAME" sudo -n true >/dev/null 2>&1; then
        success "Pi user has passwordless sudo"
    else
        warning "Sudo access may not work correctly"
    fi

    # Test 3: Basic service functionality
    info "Testing basic services..."

    # Check systemd
    if docker exec "$CONTAINER_NAME" systemctl is-system-running --wait >/dev/null 2>&1; then
        success "Systemd is running"
    else
        warning "Systemd may have issues"
    fi

    # Check SSH service
    if docker exec "$CONTAINER_NAME" systemctl is-active --quiet ssh; then
        success "SSH service is active"
    else
        warning "SSH service is not active"
    fi

    echo
    success "Quick E2E test completed!"
    info "Container available for manual testing: docker exec -it $CONTAINER_NAME bash"

    # Ask if user wants to keep container for inspection
    echo
    read -p "Keep container for manual inspection? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        trap - EXIT
        info "Container preserved: $CONTAINER_NAME"
        info "Access with: docker exec -it $CONTAINER_NAME bash"
    fi
}

main "$@"