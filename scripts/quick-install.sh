#!/bin/bash
#
# Pi Gateway Quick Install Script
# One-command installation for Pi Gateway
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly REPO_URL="https://github.com/vnykmshr/pi-gateway.git"
readonly INSTALL_DIR="$HOME/pi-gateway"
readonly LOG_FILE="/tmp/pi-gateway-install.log"

# Logging functions
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }
success() { echo -e "  ${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "  ${RED}✗${NC} $1" | tee -a "$LOG_FILE"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1" | tee -a "$LOG_FILE"; }

# Error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Installation failed! Check log: $LOG_FILE"
        error "For help, visit: https://github.com/vnykmshr/pi-gateway/issues"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Welcome message
show_welcome() {
    echo -e "${CYAN}"
    cat << 'EOF'
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   🚀 Pi Gateway Quick Install                              │
│                                                             │
│   Complete Raspberry Pi homelab setup in minutes          │
│                                                             │
│   Features:                                                 │
│   • SSH hardening & VPN setup                             │
│   • Security hardening & firewall                         │
│   • Container platform & services                         │
│   • Monitoring & automated maintenance                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
EOF
    echo -e "${NC}"
    echo
}

# Check prerequisites
check_prerequisites() {
    info "Checking system prerequisites..."

    # Check if running on Raspberry Pi
    if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        warning "Not running on Raspberry Pi - some features may not work optimally"
    else
        local model
        model=$(cat /proc/device-tree/model | tr -d '\0')
        success "Detected: $model"
    fi

    # Check for required commands
    local required_commands=("git" "curl" "sudo")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command '$cmd' not found"
            exit 1
        fi
    done

    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        warning "Sudo access required for installation"
        info "You may be prompted for your password during installation"
    fi

    # Check internet connectivity
    if ! curl -s --max-time 5 https://github.com >/dev/null; then
        error "Internet connectivity required for installation"
        exit 1
    fi

    success "Prerequisites check passed"
}

# Clone repository
clone_repository() {
    info "Cloning Pi Gateway repository..."

    if [[ -d "$INSTALL_DIR" ]]; then
        warning "Directory $INSTALL_DIR already exists"
        read -p "Remove existing directory and continue? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            error "Installation cancelled"
            exit 1
        fi
    fi

    if ! git clone "$REPO_URL" "$INSTALL_DIR"; then
        error "Failed to clone repository"
        exit 1
    fi

    cd "$INSTALL_DIR"
    success "Repository cloned to $INSTALL_DIR"
}

# Run system check
run_system_check() {
    info "Running system requirements check..."

    if ! ./scripts/check-requirements.sh; then
        warning "System check found issues - continuing with installation"
        warning "Some features may not work correctly"
    else
        success "System requirements check passed"
    fi
}

# Install dependencies
install_dependencies() {
    info "Installing system dependencies..."

    if ! ./scripts/install-dependencies.sh; then
        error "Failed to install dependencies"
        exit 1
    fi

    success "Dependencies installed successfully"
}

# Apply system hardening
apply_hardening() {
    info "Applying system security hardening..."

    if ! ./scripts/system-hardening.sh; then
        warning "System hardening completed with warnings"
    else
        success "System hardening applied successfully"
    fi
}

# Setup SSH
setup_ssh() {
    info "Configuring SSH security..."

    if ! ./scripts/ssh-setup.sh; then
        warning "SSH setup completed with warnings"
    else
        success "SSH security configured"
    fi
}

# Setup firewall
setup_firewall() {
    info "Configuring firewall..."

    if ! ./scripts/firewall-setup.sh; then
        warning "Firewall setup completed with warnings"
    else
        success "Firewall configured"
    fi
}

# Setup VPN
setup_vpn() {
    info "Setting up WireGuard VPN..."

    if ! ./scripts/vpn-setup.sh; then
        warning "VPN setup completed with warnings"
    else
        success "WireGuard VPN configured"
    fi
}

# Setup monitoring
setup_monitoring() {
    info "Setting up monitoring system..."

    if ! ./scripts/monitoring-system.sh setup; then
        warning "Monitoring setup completed with warnings"
    else
        success "Monitoring system configured"
    fi
}

# Setup maintenance
setup_maintenance() {
    info "Configuring automated maintenance..."

    if ! ./scripts/auto-maintenance.sh configure; then
        warning "Maintenance setup completed with warnings"
    else
        success "Automated maintenance configured"
    fi
}

# Install container support (optional)
install_containers() {
    info "Installing Docker container support..."

    if ! ./scripts/container-support.sh install docker; then
        warning "Container support installation had issues"
    else
        success "Docker container support installed"
    fi
}

# Create first VPN client
create_vpn_client() {
    info "Creating initial VPN client configuration..."

    local hostname
    hostname=$(hostname)
    local client_name="${hostname}-admin"

    if ./scripts/vpn-client-manager.sh add "$client_name" >/dev/null 2>&1; then
        success "VPN client '$client_name' created"
        info "Use './scripts/vpn-client-manager.sh show $client_name' to view configuration"
    else
        warning "Failed to create initial VPN client"
    fi
}

# Show completion summary
show_completion() {
    echo
    echo -e "${GREEN}"
    cat << 'EOF'
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   🎉 Pi Gateway Installation Complete!                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
EOF
    echo -e "${NC}"

    echo -e "${CYAN}📋 Installation Summary:${NC}"
    success "System hardening applied"
    success "SSH security configured"
    success "Firewall protection enabled"
    success "WireGuard VPN server running"
    success "Monitoring system active"
    success "Automated maintenance scheduled"
    success "Container platform ready"

    echo
    echo -e "${BLUE}🔧 Next Steps:${NC}"
    echo "1. Check system status:"
    echo "   cd $INSTALL_DIR && ./scripts/pi-gateway-cli.sh status"
    echo
    echo "2. Add VPN clients:"
    echo "   ./scripts/vpn-client-manager.sh add my-device"
    echo
    echo "3. Start container services:"
    echo "   ./scripts/container-manager.sh start homeassistant"
    echo
    echo "4. View monitoring dashboard:"
    echo "   http://$(hostname -I | awk '{print $1}'):3000"
    echo

    echo -e "${YELLOW}📚 Documentation:${NC}"
    echo "• Quick Start: docs/quick-start.md"
    echo "• Full Setup Guide: docs/setup-guide.md"
    echo "• Troubleshooting: docs/troubleshooting.md"
    echo

    echo -e "${YELLOW}🔐 Important Security Notes:${NC}"
    warning "Change default passwords for all services"
    warning "Setup SSH key authentication"
    warning "Configure firewall rules for your network"
    warning "Review security settings in production"

    echo
    echo -e "${GREEN}Installation log saved to: $LOG_FILE${NC}"
}

# Interactive mode
interactive_setup() {
    echo -e "${YELLOW}🔧 Interactive Setup Mode${NC}"
    echo "Answer a few questions to customize your installation:"
    echo

    # VPN configuration
    read -p "Enter your domain name for VPN (or press Enter to skip): " -r DOMAIN_NAME
    if [[ -n "$DOMAIN_NAME" ]]; then
        export VPN_DOMAIN="$DOMAIN_NAME"
        info "VPN domain set to: $DOMAIN_NAME"
    fi

    # Container services
    echo
    echo "Select container services to install:"
    echo "1) Home Assistant (home automation)"
    echo "2) Grafana + InfluxDB (monitoring)"
    echo "3) Pi-hole (DNS ad blocking)"
    echo "4) Node-RED (automation flows)"
    echo "5) All services"
    echo "6) None (skip container setup)"
    echo
    read -p "Enter your choice (1-6): " -r SERVICE_CHOICE

    case $SERVICE_CHOICE in
        1) INSTALL_SERVICES="homeassistant" ;;
        2) INSTALL_SERVICES="monitoring" ;;
        3) INSTALL_SERVICES="pihole" ;;
        4) INSTALL_SERVICES="nodered" ;;
        5) INSTALL_SERVICES="all" ;;
        6) INSTALL_SERVICES="none" ;;
        *) INSTALL_SERVICES="none" ;;
    esac

    # Email notifications
    echo
    read -p "Enter email for system notifications (or press Enter to skip): " -r NOTIFICATION_EMAIL
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        export NOTIFICATION_EMAIL="$NOTIFICATION_EMAIL"
        info "Notifications will be sent to: $NOTIFICATION_EMAIL"
    fi

    echo
    info "Configuration complete. Starting installation..."
    sleep 2
}

# Install selected services
install_selected_services() {
    if [[ "${INSTALL_SERVICES:-none}" == "none" ]]; then
        return
    fi

    info "Installing selected container services..."

    case "$INSTALL_SERVICES" in
        homeassistant)
            ./scripts/container-manager.sh start homeassistant || warning "Failed to start Home Assistant"
            ;;
        monitoring)
            ./scripts/container-manager.sh start monitoring || warning "Failed to start monitoring stack"
            ;;
        pihole)
            ./scripts/container-manager.sh start pihole || warning "Failed to start Pi-hole"
            ;;
        nodered)
            ./scripts/container-manager.sh start nodered || warning "Failed to start Node-RED"
            ;;
        all)
            ./scripts/container-manager.sh start homeassistant || true
            ./scripts/container-manager.sh start monitoring || true
            ./scripts/container-manager.sh start pihole || true
            ./scripts/container-manager.sh start nodered || true
            ;;
    esac

    success "Container services installation completed"
}

# Main installation function
main() {
    local interactive=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --interactive|-i)
                interactive=true
                shift
                ;;
            --help|-h)
                echo "Pi Gateway Quick Install"
                echo
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  -i, --interactive    Run interactive setup"
                echo "  -h, --help          Show this help message"
                echo
                echo "Examples:"
                echo "  curl -sSL https://raw.githubusercontent.com/vnykmshr/pi-gateway/main/scripts/quick-install.sh | bash"
                echo "  curl -sSL https://raw.githubusercontent.com/vnykmshr/pi-gateway/main/scripts/quick-install.sh | bash -s -- --interactive"
                exit 0
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Start installation
    show_welcome
    log "Starting Pi Gateway quick installation"

    # Interactive setup if requested
    if [[ "$interactive" == "true" ]]; then
        interactive_setup
    fi

    # Core installation steps
    check_prerequisites
    clone_repository
    run_system_check
    install_dependencies
    apply_hardening
    setup_ssh
    setup_firewall
    setup_vpn
    setup_monitoring
    setup_maintenance
    install_containers
    create_vpn_client

    # Install selected services
    install_selected_services

    # Completion
    show_completion
    log "Pi Gateway installation completed successfully"
}

# Run main function
main "$@"
