#!/bin/bash
#
# Pi Gateway Quick Install
# One-command installation for Pi Gateway homelab automation
#

set -euo pipefail

# Configuration
readonly REPO_URL="https://github.com/vnykmshr/pi-gateway.git"
readonly INSTALL_DIR="$HOME/pi-gateway"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Simple logging
success() { echo -e "  ${GREEN}✓${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1" >&2; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

# Error handling
cleanup() {
    local exit_code=$?
    [[ $exit_code -ne 0 ]] && error "Installation failed! For help: https://github.com/vnykmshr/pi-gateway/issues"
    exit $exit_code
}
trap cleanup EXIT

# Main installation
main() {
    echo -e "${CYAN}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│   🚀 Pi Gateway Quick Install                              │"
    echo "│   Complete Raspberry Pi homelab setup in minutes          │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo -e "${NC}"

    # Parse arguments
    local interactive=false
    [[ "${1:-}" == "--interactive" ]] && interactive=true

    # Prerequisites
    info "Checking prerequisites..."
    command -v git >/dev/null || { error "Git is required"; exit 1; }
    command -v sudo >/dev/null || { error "Sudo is required"; exit 1; }

    # Download
    info "Downloading Pi Gateway..."
    if [[ -d "$INSTALL_DIR" ]]; then
        cd "$INSTALL_DIR" && git pull
    else
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi

    # Install
    cd "$INSTALL_DIR"
    info "Starting installation..."
    if [[ "$interactive" == "true" ]]; then
        sudo ./setup.sh
    else
        sudo ./setup.sh --non-interactive
    fi

    success "Pi Gateway installation completed!"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Generate SSH keys: ssh-keygen -t ed25519"
    echo "  2. Add VPN client: sudo ./scripts/vpn-client-manager.sh add my-device"
    echo "  3. Check status: ./scripts/status-dashboard.sh"
}

main "$@"
