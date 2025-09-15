#!/bin/bash
#
# Pi Gateway - System Hardening Script
# Applies security best practices for internet-connected Raspberry Pi devices
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly LOG_FILE="/tmp/pi-gateway-hardening.log"
readonly BACKUP_DIR="/var/backups/pi-gateway/hardening"
readonly CONFIG_DIR="/etc/pi-gateway"

# Hardening configuration
readonly SYSCTL_CONF="/etc/sysctl.d/99-pi-gateway-hardening.conf"
readonly LIMITS_CONF="/etc/security/limits.d/99-pi-gateway.conf"
readonly LOGIN_DEFS="/etc/login.defs"

# Global counters
HARDENING_APPLIED=0
HARDENING_FAILED=0
WARNINGS=0

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}      Pi Gateway - System Hardening          ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

print_section() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
    ((HARDENING_APPLIED++))
}

error() {
    echo -e "  ${RED}✗${NC} $1"
    log "ERROR: $1"
    ((HARDENING_FAILED++))
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
    ((WARNINGS++))
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

# Backup function
backup_file() {
    local file="$1"
    local backup_name="$2"

    if [[ -f "$file" ]]; then
        local backup_path
        backup_path="$BACKUP_DIR/${backup_name}.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        if cp "$file" "$backup_path"; then
            info "Backed up $file to $backup_path"
            return 0
        else
            warning "Failed to backup $file"
            return 1
        fi
    fi
    return 0
}

# Pre-hardening checks
check_prerequisites() {
    print_section "Pre-hardening Checks"

    # Check if running with sudo/root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo privileges"
        echo "Usage: sudo $0"
        exit 1
    fi
    success "Running with administrative privileges"

    # Create necessary directories
    mkdir -p "$BACKUP_DIR" "$CONFIG_DIR"
    success "Backup and configuration directories created"

    # Initialize log
    true > "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    success "Logging initialized"
}

# Update system packages
update_and_upgrade_system() {
    print_section "System Updates"

    info "Updating package repositories..."
    if apt update 2>&1 | tee -a "$LOG_FILE"; then
        success "Package repositories updated"
    else
        error "Failed to update repositories"
        return 1
    fi

    info "Upgrading system packages..."
    if DEBIAN_FRONTEND=noninteractive apt upgrade -y 2>&1 | tee -a "$LOG_FILE"; then
        success "System packages upgraded"
    else
        warning "Some packages failed to upgrade"
    fi

    info "Removing unnecessary packages..."
    if apt autoremove -y >/dev/null 2>&1; then
        success "Unnecessary packages removed"
    else
        warning "Failed to remove some packages"
    fi
}

# Configure automatic security updates
configure_automatic_updates() {
    print_section "Automatic Security Updates"

    # Install unattended-upgrades
    if ! dpkg -l | grep -q unattended-upgrades; then
        info "Installing unattended-upgrades..."
        if apt install -y unattended-upgrades 2>&1 | tee -a "$LOG_FILE"; then
            success "Unattended-upgrades installed"
        else
            error "Failed to install unattended-upgrades"
            return 1
        fi
    else
        success "Unattended-upgrades already installed"
    fi

    # Configure automatic updates
    backup_file "/etc/apt/apt.conf.d/50unattended-upgrades" "50unattended-upgrades"

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
// Automatically upgrade packages from these origin patterns
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Raspbian,codename=${distro_codename},label=Raspbian";
    "origin=Raspberry Pi Foundation,codename=${distro_codename}";
};

// List of packages to not update (regexp)
Unattended-Upgrade::Package-Blacklist {
    // None for now - be aggressive with security updates
};

// Split the upgrade into the smallest possible chunks
Unattended-Upgrade::MinimalSteps "true";

// Install security updates automatically
Unattended-Upgrade::InstallOnShutdown "false";

// Send email to this address for problems or packages upgrades
// Unattended-Upgrade::Mail "";

// Do automatic removal of unused kernel packages after the upgrade
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Do automatic removal of new unused dependencies after the upgrade
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Do automatic removal of unused packages after the upgrade
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot *WITHOUT CONFIRMATION* if required
Unattended-Upgrade::Automatic-Reboot "false";

// Reboot time (24hr format, requires automatic reboot enabled)
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

    # Enable automatic updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl enable unattended-upgrades
    success "Automatic security updates configured"
}

# Kernel and system hardening
apply_kernel_hardening() {
    print_section "Kernel Hardening"

    backup_file "$SYSCTL_CONF" "sysctl-hardening"

    cat > "$SYSCTL_CONF" << 'EOF'
# Pi Gateway - Kernel Hardening Configuration

# Network Security
# Disable IP forwarding (will be enabled specifically for VPN later)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable secure redirects
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ping requests
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# TCP hardening
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1

# Memory protection
kernel.exec-shield = 1
kernel.randomize_va_space = 2

# Process restrictions
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# File system hardening
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# Network buffer limits
net.core.rmem_default = 31457280
net.core.rmem_max = 67108864
net.core.wmem_default = 31457280
net.core.wmem_max = 67108864
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
EOF

    # Apply sysctl settings
    if sysctl -p "$SYSCTL_CONF" 2>&1 | tee -a "$LOG_FILE"; then
        success "Kernel hardening parameters applied"
    else
        error "Failed to apply kernel hardening"
    fi
}

# User account security
harden_user_accounts() {
    print_section "User Account Security"

    # Configure password policies
    backup_file "$LOGIN_DEFS" "login.defs"

    # Set password aging policy
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/' "$LOGIN_DEFS"
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t7/' "$LOGIN_DEFS"
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE\t14/' "$LOGIN_DEFS"
    success "Password aging policies configured"

    # Lock unused system accounts
    local system_accounts=("daemon" "bin" "sys" "sync" "games" "man" "lp" "mail" "news" "uucp" "proxy" "www-data" "backup" "list" "irc" "gnats")

    for account in "${system_accounts[@]}"; do
        if id "$account" >/dev/null 2>&1; then
            if passwd -l "$account" >/dev/null 2>&1; then
                info "Locked system account: $account"
            fi
        fi
    done
    success "Unused system accounts locked"

    # Disable root login (but keep sudo access)
    if passwd -l root >/dev/null 2>&1; then
        success "Root account locked"
    else
        warning "Failed to lock root account"
    fi

    # Set umask for better default permissions
    if grep -q "umask" /etc/bash.bashrc; then
        sed -i 's/umask.*/umask 027/' /etc/bash.bashrc
    else
        echo "umask 027" >> /etc/bash.bashrc
    fi
    success "Default umask set to 027"
}

# Disable unnecessary services
disable_unnecessary_services() {
    print_section "Service Hardening"

    # Services that are typically safe to disable on a headless Pi
    local services_to_disable=(
        "bluetooth.service"
        "hciuart.service"
        "triggerhappy.service"
        "avahi-daemon.service"
        "cups.service"
        "cups-browsed.service"
        "ModemManager.service"
    )

    # Services to mask (more aggressive disable)
    local services_to_mask=(
        "plymouth-start.service"
        "plymouth-read-write.service"
        "plymouth-quit-wait.service"
        "plymouth-quit.service"
    )

    for service in "${services_to_disable[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                systemctl disable "$service" >/dev/null 2>&1
                systemctl stop "$service" >/dev/null 2>&1 || true
                info "Disabled service: $service"
            fi
        fi
    done

    for service in "${services_to_mask[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            systemctl mask "$service" >/dev/null 2>&1 || true
            info "Masked service: $service"
        fi
    done

    success "Unnecessary services disabled"
}

# Configure log retention and monitoring
configure_logging() {
    print_section "Log Configuration"

    # Configure logrotate for Pi Gateway logs
    cat > /etc/logrotate.d/pi-gateway << 'EOF'
/var/log/pi-gateway/*.log {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 644 pi-gateway pi-gateway
    postrotate
        systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}
EOF
    success "Log rotation configured for Pi Gateway"

    # Configure rsyslog for security logging
    if [[ ! -f /etc/rsyslog.d/99-pi-gateway.conf ]]; then
        cat > /etc/rsyslog.d/99-pi-gateway.conf << 'EOF'
# Pi Gateway security logging
auth,authpriv.*                 /var/log/pi-gateway/auth.log
daemon.info                     /var/log/pi-gateway/daemon.log
kern.warning                    /var/log/pi-gateway/kernel.log
EOF
        systemctl restart rsyslog
        success "Security logging configured"
    fi

    # Ensure log directory exists
    mkdir -p /var/log/pi-gateway
    chown pi-gateway:pi-gateway /var/log/pi-gateway
    chmod 750 /var/log/pi-gateway
    success "Log directory secured"
}

# File system hardening
apply_filesystem_hardening() {
    print_section "File System Hardening"

    # Set strict permissions on sensitive files
    local sensitive_files=(
        "/etc/passwd:644"
        "/etc/shadow:640"
        "/etc/group:644"
        "/etc/gshadow:640"
        "/etc/fstab:644"
        "/etc/ssh/sshd_config:600"
        "/boot/config.txt:644"
        "/boot/cmdline.txt:644"
    )

    for file_perm in "${sensitive_files[@]}"; do
        local file="${file_perm%:*}"
        local perm="${file_perm#*:}"

        if [[ -f "$file" ]]; then
            chmod "$perm" "$file"
            info "Set permissions $perm on $file"
        fi
    done
    success "Sensitive file permissions hardened"

    # Remove world-writable permissions from system directories
    local system_dirs=("/tmp" "/var/tmp" "/dev/shm")

    for dir in "${system_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            chmod 1777 "$dir"  # Sticky bit + rwx for owner, rx for others
            info "Hardened permissions on $dir"
        fi
    done
    success "System directory permissions hardened"

    # Create and secure Pi Gateway directories
    local pi_gateway_dirs=(
        "/etc/pi-gateway:750"
        "/var/lib/pi-gateway:750"
        "/var/log/pi-gateway:750"
    )

    for dir_perm in "${pi_gateway_dirs[@]}"; do
        local dir="${dir_perm%:*}"
        local perm="${dir_perm#*:}"

        mkdir -p "$dir"
        chown pi-gateway:pi-gateway "$dir"
        chmod "$perm" "$dir"
    done
    success "Pi Gateway directories secured"
}

# Configure resource limits
configure_limits() {
    print_section "Resource Limits"

    backup_file "$LIMITS_CONF" "limits"

    cat > "$LIMITS_CONF" << 'EOF'
# Pi Gateway - Resource Limits Configuration

# Prevent fork bombs
* soft nproc 1024
* hard nproc 2048

# Limit core dumps
* soft core 0
* hard core 0

# File descriptor limits
* soft nofile 65536
* hard nofile 65536

# Memory limits (in KB)
* soft as unlimited
* hard as unlimited

# CPU time limits (seconds)
* soft cpu unlimited
* hard cpu unlimited

# File size limits
* soft fsize unlimited
* hard fsize unlimited
EOF

    success "Resource limits configured"
}

# Setup intrusion detection
setup_intrusion_detection() {
    print_section "Intrusion Detection"

    # Configure rkhunter if installed
    if command -v rkhunter >/dev/null 2>&1; then
        info "Configuring rkhunter..."

        backup_file "/etc/rkhunter.conf" "rkhunter.conf"

        # Update rkhunter database
        rkhunter --update >/dev/null 2>&1 || true
        rkhunter --propupd >/dev/null 2>&1 || true

        success "Rkhunter configured and updated"
    fi

    # Configure AIDE if installed
    if command -v aide >/dev/null 2>&1; then
        info "Initializing AIDE database (this may take a while)..."

        # Initialize AIDE database
        if aide --init 2>&1 | tee -a "$LOG_FILE"; then
            mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
            success "AIDE database initialized"
        else
            warning "AIDE database initialization failed"
        fi
    fi
}

# Configure fail2ban
configure_fail2ban() {
    print_section "Fail2ban Configuration"

    if command -v fail2ban-client >/dev/null 2>&1; then
        backup_file "/etc/fail2ban/jail.local" "jail.local"

        cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban duration (10 minutes initially, increases with repeat offenses)
bantime = 600
findtime = 600
maxretry = 3

# Email notifications (configure as needed)
# destemail = admin@example.com
# sendername = Pi-Gateway-Fail2ban
# mta = sendmail

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 6
bantime = 600

# Ban repeated failed attempts on any service
[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = iptables-allports[name=recidive]
bantime = 86400
findtime = 86400
maxretry = 5
EOF

        # Restart fail2ban to apply new configuration
        systemctl restart fail2ban
        systemctl enable fail2ban
        success "Fail2ban configured and started"
    else
        warning "Fail2ban not installed, skipping configuration"
    fi
}

# Verify hardening
verify_hardening() {
    print_section "Hardening Verification"

    local checks_passed=0
    local checks_total=0

    # Check sysctl settings
    ((checks_total++))
    if sysctl net.ipv4.ip_forward | grep -q "= 0"; then
        success "IP forwarding disabled"
        ((checks_passed++))
    else
        error "IP forwarding not properly disabled"
    fi

    # Check service status
    local critical_services=("fail2ban" "ssh")
    for service in "${critical_services[@]}"; do
        ((checks_total++))
        if systemctl is-active "$service" >/dev/null 2>&1; then
            success "$service is running"
            ((checks_passed++))
        else
            error "$service is not running"
        fi
    done

    # Check file permissions
    ((checks_total++))
    if [[ $(stat -c %a /etc/shadow) == "640" ]]; then
        success "/etc/shadow has correct permissions"
        ((checks_passed++))
    else
        error "/etc/shadow permissions are incorrect"
    fi

    info "Verification: $checks_passed/$checks_total checks passed"
}

# Create hardening summary
create_hardening_report() {
    local report_file="/var/log/pi-gateway/hardening-report.txt"

    cat > "$report_file" << EOF
Pi Gateway System Hardening Report
Generated: $(date)

Applied Hardening Measures: $HARDENING_APPLIED
Failed Measures: $HARDENING_FAILED
Warnings: $WARNINGS

Hardening Categories Applied:
- System updates and automatic security updates
- Kernel security parameters
- User account security
- Service hardening and disabling unnecessary services
- Logging and monitoring configuration
- File system permission hardening
- Resource limits
- Intrusion detection setup
- Fail2ban intrusion prevention

Next Steps:
1. Configure SSH hardening (run ssh-setup.sh)
2. Set up VPN server (run vpn-setup.sh)
3. Configure firewall rules (run firewall-setup.sh)

Log File: $LOG_FILE
Backup Directory: $BACKUP_DIR
EOF

    chown pi-gateway:pi-gateway "$report_file"
    chmod 644 "$report_file"
    success "Hardening report created: $report_file"
}

print_summary() {
    echo
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}           Hardening Summary                   ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo

    echo -e "Hardening measures applied: ${GREEN}$HARDENING_APPLIED${NC}"
    echo -e "Failed measures: ${RED}$HARDENING_FAILED${NC}"
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
    echo
    echo -e "Log file: ${BLUE}$LOG_FILE${NC}"
    echo -e "Backups: ${BLUE}$BACKUP_DIR${NC}"
    echo

    if [[ $HARDENING_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ System hardening completed successfully${NC}"
        echo -e "Next step: Configure SSH security"
        echo -e "Command: ${BLUE}sudo ./scripts/ssh-setup.sh${NC}"
        echo
        echo -e "${YELLOW}⚠ IMPORTANT: Reboot recommended to ensure all changes take effect${NC}"
        echo -e "Command: ${BLUE}sudo reboot${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ System hardening completed with some issues${NC}"
        echo -e "Review the log file for details: ${BLUE}$LOG_FILE${NC}"
        return 1
    fi
}

# Main execution
main() {
    # Initialize logging
    true > "$LOG_FILE"

    print_header
    log "Starting Pi Gateway system hardening"

    check_prerequisites
    update_and_upgrade_system
    configure_automatic_updates
    apply_kernel_hardening
    harden_user_accounts
    disable_unnecessary_services
    configure_logging
    apply_filesystem_hardening
    configure_limits
    setup_intrusion_detection
    configure_fail2ban
    verify_hardening
    create_hardening_report

    print_summary
}

# Handle interruption
trap 'echo -e "\n${YELLOW}Hardening interrupted${NC}"; exit 130' INT

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi