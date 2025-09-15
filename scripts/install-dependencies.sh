#!/bin/bash
#
# Pi Gateway - Dependency Installer
# Installs all required packages and dependencies for Pi Gateway setup
#

set -euo pipefail

# Source dry-run utilities if available
if [[ -f "$(dirname "$0")/../tests/mocks/common.sh" ]]; then
    source "$(dirname "$0")/../tests/mocks/common.sh"
fi

if [[ -f "$(dirname "$0")/../tests/mocks/system.sh" ]]; then
    source "$(dirname "$0")/../tests/mocks/system.sh"
fi

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly LOG_FILE="/tmp/pi-gateway-install-deps.log"
readonly BACKUP_DIR="/var/backups/pi-gateway"

# Package categories
readonly CORE_PACKAGES=(
    "curl"
    "wget"
    "git"
    "unzip"
    "software-properties-common"
    "apt-transport-https"
    "ca-certificates"
    "gnupg"
    "lsb-release"
)

readonly SECURITY_PACKAGES=(
    "ufw"
    "fail2ban"
    "rkhunter"
    "chkrootkit"
    "logwatch"
    "aide"
)

readonly NETWORK_PACKAGES=(
    "openssh-server"
    "wireguard"
    "wireguard-tools"
    "resolvconf"
    "iptables-persistent"
    "netfilter-persistent"
)

readonly REMOTE_DESKTOP_PACKAGES=(
    "realvnc-vnc-server"
    "realvnc-vnc-viewer"
    "xrdp"
)

readonly DDNS_PACKAGES=(
    "ddclient"
    "dnsutils"
)

readonly MONITORING_PACKAGES=(
    "htop"
    "iotop"
    "nethogs"
    "tcpdump"
    "nmap"
)

readonly OPTIONAL_PACKAGES=(
    "python3"
    "python3-pip"
    "qrencode"
    "tree"
    "vim"
    "nano"
)

# Global status tracking
PACKAGES_INSTALLED=0
PACKAGES_FAILED=0
SERVICES_CONFIGURED=0

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Pi Gateway - Dependency Installation      ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

print_section() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

error() {
    echo -e "  ${RED}✗${NC} $1"
    log "ERROR: $1"
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

# Pre-installation checks
check_prerequisites() {
    print_section "Pre-installation Checks"

    # Check if running with sudo/root (skip in dry-run mode)
    if [[ $EUID -ne 0 && "$DRY_RUN" != "true" ]]; then
        error "This script must be run with sudo privileges"
        echo "Usage: sudo $0"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        success "Running in dry-run mode (sudo check skipped)"
    else
        success "Running with administrative privileges"
    fi

    # Check internet connectivity
    if (is_dry_run || is_mocked "network") && [[ "${MOCK_INTERNET_CONNECTIVITY:-true}" == "true" ]]; then
        success "Internet connectivity verified (mocked)"
    elif ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        success "Internet connectivity verified"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            success "Internet connectivity skipped in dry-run mode"
        else
            error "No internet connectivity. Cannot download packages"
            exit 1
        fi
    fi

    # Create backup directory
    execute_command "mkdir -p \"$BACKUP_DIR\""
    success "Backup directory created: $BACKUP_DIR"

    # Create log file
    execute_command "touch \"$LOG_FILE\""
    execute_command "chmod 644 \"$LOG_FILE\""
    success "Log file initialized: $LOG_FILE"
}

# System update
update_system() {
    print_section "System Update"

    info "Updating package repositories..."
    if (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt update) || apt update 2>&1 | tee -a "$LOG_FILE"; then
        success "Package repositories updated"
    else
        error "Failed to update package repositories"
        exit 1
    fi

    info "Upgrading existing packages..."
    if (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt upgrade -y) || apt upgrade -y 2>&1 | tee -a "$LOG_FILE"; then
        success "System packages upgraded"
    else
        warning "Some packages failed to upgrade"
    fi

    # Clean up
    (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt autoremove -y) || apt autoremove -y >/dev/null 2>&1
    (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt autoclean) || apt autoclean >/dev/null 2>&1
    success "Package cache cleaned"
}

# Package installation helper
install_package_category() {
    local category_name="$1"
    shift
    local packages=("$@")

    print_section "$category_name"

    for package in "${packages[@]}"; do
        info "Installing $package..."

        if (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt install -y "$package") || apt install -y "$package" 2>&1 | tee -a "$LOG_FILE"; then
            success "$package installed successfully"
            ((PACKAGES_INSTALLED++))
        else
            error "Failed to install $package"
            ((PACKAGES_FAILED++))
        fi
    done
}

# Special installation handlers
install_wireguard() {
    print_section "WireGuard Installation"

    # Check if WireGuard is available in repos
    if apt-cache show wireguard >/dev/null 2>&1; then
        info "Installing WireGuard from official repositories..."
        if (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt install -y wireguard wireguard-tools) || apt install -y wireguard wireguard-tools 2>&1 | tee -a "$LOG_FILE"; then
            success "WireGuard installed successfully"
            ((PACKAGES_INSTALLED++))
        else
            error "Failed to install WireGuard"
            ((PACKAGES_FAILED++))
            return 1
        fi
    else
        warning "WireGuard not available in official repositories"
        info "Attempting to install from backports..."

        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" > /etc/apt/sources.list.d/backports.list
        (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt update) || apt update

        if (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt install -y -t "$(lsb_release -sc)"-backports wireguard) || apt install -y -t "$(lsb_release -sc)"-backports wireguard 2>&1 | tee -a "$LOG_FILE"; then
            success "WireGuard installed from backports"
            ((PACKAGES_INSTALLED++))
        else
            error "Failed to install WireGuard from backports"
            ((PACKAGES_FAILED++))
        fi
    fi

    # Verify WireGuard installation
    if command -v wg >/dev/null 2>&1; then
        local wg_version
        wg_version=$(wg --version 2>/dev/null | head -n1)
        success "WireGuard tools verified: $wg_version"
    else
        error "WireGuard tools not found after installation"
    fi
}

install_realvnc() {
    print_section "RealVNC Installation"

    # Check if we're on Raspberry Pi OS (RealVNC comes pre-installed)
    if [[ -f /etc/os-release ]] && grep -q "Raspberry Pi OS" /etc/os-release; then
        info "Raspberry Pi OS detected - RealVNC should be pre-installed"

        if systemctl list-unit-files | grep -q vncserver; then
            success "RealVNC server found"
            ((PACKAGES_INSTALLED++))
        else
            warning "RealVNC server not found, attempting manual installation"
            install_package_category "RealVNC Fallback" "${REMOTE_DESKTOP_PACKAGES[@]}"
        fi
    else
        info "Installing alternative VNC server..."
        if (command -v mock_apt >/dev/null 2>&1 && (is_dry_run || is_mocked "system") && mock_apt install -y tightvncserver) || apt install -y tightvncserver 2>&1 | tee -a "$LOG_FILE"; then
            success "TightVNC server installed as alternative"
            ((PACKAGES_INSTALLED++))
        else
            error "Failed to install VNC server"
            ((PACKAGES_FAILED++))
        fi
    fi
}

configure_services() {
    print_section "Service Configuration"

    # Enable SSH service
    if systemctl enable ssh 2>&1 | tee -a "$LOG_FILE"; then
        success "SSH service enabled"
        ((SERVICES_CONFIGURED++))
    else
        warning "Failed to enable SSH service"
    fi

    # Configure UFW (but don't enable yet)
    if command -v ufw >/dev/null 2>&1; then
        info "Configuring UFW firewall..."
        ufw --force reset >/dev/null 2>&1
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        success "UFW firewall configured (not enabled yet)"
        ((SERVICES_CONFIGURED++))
    fi

    # Configure fail2ban
    if command -v fail2ban-client >/dev/null 2>&1; then
        info "Configuring fail2ban..."
        systemctl enable fail2ban >/dev/null 2>&1
        success "Fail2ban enabled"
        ((SERVICES_CONFIGURED++))
    fi

    # Create systemd override directories
    local services=("ssh" "fail2ban" "ufw")
    for service in "${services[@]}"; do
        mkdir -p "/etc/systemd/system/$service.service.d"
    done
    success "Systemd override directories created"
}

create_service_user() {
    print_section "Service User Setup"

    local pi_gateway_user="pi-gateway"

    # Create dedicated user for Pi Gateway services
    if ! id "$pi_gateway_user" >/dev/null 2>&1; then
        info "Creating Pi Gateway service user..."
        if useradd -r -s /bin/false -d /var/lib/pi-gateway -m "$pi_gateway_user" 2>&1 | tee -a "$LOG_FILE"; then
            success "Pi Gateway service user created"
        else
            warning "Failed to create Pi Gateway service user"
        fi
    else
        success "Pi Gateway service user already exists"
    fi

    # Create service directories
    local service_dirs=(
        "/var/lib/pi-gateway"
        "/var/log/pi-gateway"
        "/etc/pi-gateway"
    )

    for dir in "${service_dirs[@]}"; do
        mkdir -p "$dir"
        chown "$pi_gateway_user:$pi_gateway_user" "$dir"
        chmod 750 "$dir"
    done
    success "Service directories created and secured"
}

install_python_packages() {
    print_section "Python Packages"

    if command -v pip3 >/dev/null 2>&1; then
        local python_packages=(
            "requests"
            "cryptography"
            "qrcode"
            "pillow"
        )

        for package in "${python_packages[@]}"; do
            info "Installing Python package: $package"
            if pip3 install "$package" 2>&1 | tee -a "$LOG_FILE"; then
                success "Python package $package installed"
            else
                warning "Failed to install Python package $package"
            fi
        done
    else
        warning "pip3 not available, skipping Python packages"
    fi
}

backup_original_configs() {
    print_section "Configuration Backup"

    local config_files=(
        "/etc/ssh/sshd_config"
        "/etc/ufw/ufw.conf"
        "/etc/fail2ban/jail.conf"
        "/etc/ddclient.conf"
    )

    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            local backup_file
            backup_file="$BACKUP_DIR/$(basename "$config_file").$(date +%Y%m%d_%H%M%S)"
            if execute_command "cp '$config_file' '$backup_file'" 2>&1 | tee -a "$LOG_FILE"; then
                success "Backed up $config_file to $backup_file"
            else
                warning "Failed to backup $config_file"
            fi
        fi
    done
}

verify_installation() {
    print_section "Installation Verification"

    # Skip verification in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Installation verification skipped in dry-run mode"
        return 0
    fi

    local critical_commands=("ssh" "ufw" "wg" "fail2ban-client")
    local all_good=true

    for cmd in "${critical_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            success "$cmd is available and functional"
        else
            error "$cmd is missing or not functional"
            all_good=false
        fi
    done

    # Check service status
    local critical_services=("ssh")
    for service in "${critical_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            success "$service is enabled"
        else
            warning "$service is not enabled"
            all_good=false
        fi
    done

    if [[ "$all_good" == "true" ]]; then
        success "All critical components verified"
        return 0
    else
        error "Some critical components are missing"
        return 1
    fi
}

print_summary() {
    echo
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}            Installation Summary              ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo

    echo -e "Packages installed: ${GREEN}$PACKAGES_INSTALLED${NC}"
    echo -e "Package failures: ${RED}$PACKAGES_FAILED${NC}"
    echo -e "Services configured: ${BLUE}$SERVICES_CONFIGURED${NC}"
    echo
    echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
    echo -e "Backup directory: ${BLUE}$BACKUP_DIR${NC}"
    echo

    if [[ $PACKAGES_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All dependencies installed successfully${NC}"
        echo -e "Next step: Run the system hardening script"
        echo -e "Command: ${BLUE}sudo ./scripts/system-hardening.sh${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Some packages failed to install ($PACKAGES_FAILED failures)${NC}"
        echo -e "Check the log file for details: ${BLUE}$LOG_FILE${NC}"
        echo -e "You may need to resolve these issues before proceeding"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    # Add any cleanup tasks here
}

# Main execution
main() {
    # Initialize dry-run environment if available
    if command -v init_dry_run_environment >/dev/null 2>&1; then
        init_dry_run_environment
    fi

    # Setup mock system environment for dry-run mode
    if command -v setup_mock_system >/dev/null 2>&1; then
        setup_mock_system
    fi
    # Initialize log
    true > "$LOG_FILE"

    print_header
    log "Starting Pi Gateway dependency installation"

    # Trap for cleanup
    trap cleanup EXIT

    check_prerequisites
    update_system
    backup_original_configs

    # Install package categories
    install_package_category "Core System Packages" "${CORE_PACKAGES[@]}"
    install_package_category "Security Packages" "${SECURITY_PACKAGES[@]}"
    install_package_category "Network Packages" "${NETWORK_PACKAGES[@]}"
    install_package_category "Dynamic DNS Packages" "${DDNS_PACKAGES[@]}"
    install_package_category "Monitoring Tools" "${MONITORING_PACKAGES[@]}"
    install_package_category "Optional Packages" "${OPTIONAL_PACKAGES[@]}"

    # Special installations
    install_wireguard
    install_realvnc
    install_python_packages

    # Configuration
    create_service_user
    configure_services

    # Verification
    if verify_installation; then
        print_summary
        exit 0
    else
        print_summary
        exit 1
    fi
}

# Handle script interruption
trap 'echo -e "\n${YELLOW}Installation interrupted${NC}"; exit 130' INT

# Check if being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
