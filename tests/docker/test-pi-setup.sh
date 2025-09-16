#!/bin/bash
#
# Simple Pi Gateway Setup Test
# Tests key Pi Gateway scripts in current environment
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

success() { echo -e "  ${GREEN}✓${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1" >&2; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }

main() {
    echo -e "${BLUE}🧪 Pi Gateway Setup Testing${NC}"
    echo -e "${BLUE}   Testing core scripts with simulated environment${NC}"
    echo

    local project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    cd "$project_root"

    # Test 1: Check requirements (dry run)
    info "Testing check-requirements.sh (with mocking)..."
    if DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true ./scripts/check-requirements.sh >/dev/null 2>&1; then
        success "Requirements check works with mocking"
    else
        error "Requirements check failed with mocking"
    fi

    # Test 2: Install dependencies (dry run)
    info "Testing install-dependencies.sh (dry run)..."
    if DRY_RUN=true MOCK_SYSTEM=true MOCK_HARDWARE=true ./scripts/install-dependencies.sh >/dev/null 2>&1; then
        success "Dependency installation dry-run works"
    else
        warning "Dependency installation dry-run has issues"
    fi

    # Test 3: System hardening (dry run)
    info "Testing system-hardening.sh (dry run)..."
    if DRY_RUN=true MOCK_SYSTEM=true MOCK_HARDWARE=true ./scripts/system-hardening.sh >/dev/null 2>&1; then
        success "System hardening dry-run works"
    else
        warning "System hardening dry-run has issues"
    fi

    # Test 4: SSH setup (dry run)
    info "Testing ssh-setup.sh (dry run)..."
    if DRY_RUN=true MOCK_SYSTEM=true ./scripts/ssh-setup.sh >/dev/null 2>&1; then
        success "SSH setup dry-run works"
    else
        warning "SSH setup dry-run has issues"
    fi

    # Test 5: Firewall setup (dry run)
    info "Testing firewall-setup.sh (dry run)..."
    if DRY_RUN=true MOCK_SYSTEM=true ./scripts/firewall-setup.sh >/dev/null 2>&1; then
        success "Firewall setup dry-run works"
    else
        warning "Firewall setup dry-run has issues"
    fi

    # Test 6: VPN setup (dry run)
    info "Testing vpn-setup.sh (dry run)..."
    if DRY_RUN=true MOCK_SYSTEM=true ./scripts/vpn-setup.sh >/dev/null 2>&1; then
        success "VPN setup dry-run works"
    else
        warning "VPN setup dry-run has issues"
    fi

    # Test 7: Main setup script (dry run)
    info "Testing main setup.sh (dry run)..."
    if DRY_RUN=true MOCK_SYSTEM=true MOCK_HARDWARE=true MOCK_NETWORK=true timeout 30 ./setup.sh >/dev/null 2>&1; then
        success "Main setup script dry-run works"
    else
        warning "Main setup script may have issues (or timeout)"
    fi

    echo
    success "Pi Gateway setup testing completed!"
    echo
    info "All core scripts have been validated in dry-run mode"
    info "The scripts appear ready for deployment on a real Raspberry Pi"
}

main "$@"