#!/bin/bash
#
# Pi Gateway - Comprehensive Firewall Setup
# Advanced firewall configuration with intrusion detection and security hardening
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
readonly LOG_FILE="/tmp/pi-gateway-firewall-setup.log"
readonly CONFIG_BACKUP_DIR="/etc/pi-gateway/backups/firewall-$(date +%Y%m%d_%H%M%S)"

# Default ports and services
readonly SSH_PORT="${SSH_PORT:-2222}"
readonly WIREGUARD_PORT="${WIREGUARD_PORT:-51820}"
readonly VNC_PORT="${VNC_PORT:-5900}"
readonly RDP_PORT="${RDP_PORT:-3389}"
readonly HTTP_PORT="80"
readonly HTTPS_PORT="443"

# Fail2ban configuration
readonly FAIL2BAN_CONFIG_DIR="/etc/fail2ban"
readonly FAIL2BAN_LOCAL_CONFIG="$FAIL2BAN_CONFIG_DIR/jail.local"

# Dry-run support
DRY_RUN="${DRY_RUN:-false}"
VERBOSE_DRY_RUN="${VERBOSE_DRY_RUN:-false}"

# Load mock functions for testing if available
if [[ -f "tests/mocks/common.sh" ]]; then
    # shellcheck source=tests/mocks/common.sh
    source "tests/mocks/common.sh"
fi

if [[ -f "tests/mocks/system.sh" ]]; then
    # shellcheck source=tests/mocks/system.sh
    source "tests/mocks/system.sh"
fi

# Logging functions
log() {
    local level="$1"
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $level: $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
    log "SUCCESS" "$1"
}

error() {
    echo -e "  ${RED}✗${NC} $1"
    log "ERROR" "$1"
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    log "WARN" "$1"
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    log "INFO" "$1"
}

debug() {
    if [[ "${VERBOSE_DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${PURPLE}🔍${NC} $1"
        log "DEBUG" "$1"
    fi
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}       Pi Gateway - Firewall Setup            ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

print_section() {
    echo
    echo -e "${BLUE}--- $1 ---${NC}"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="${2:-}"

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -n "$description" ]]; then
            echo -e "  ${PURPLE}[DRY-RUN]${NC} $description"
        fi
        echo -e "  ${PURPLE}[DRY-RUN]${NC} $cmd"
        debug "Command would execute: $cmd"
        return 0
    else
        if [[ -n "$description" ]]; then
            debug "$description"
        fi
        eval "$cmd"
    fi
}

# Initialize dry-run environment
init_dry_run_environment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${PURPLE}🧪 Pi Gateway Dry-Run Mode Enabled${NC}"
        echo -e "${PURPLE}   → No actual firewall changes will be made${NC}"
        echo -e "${PURPLE}   → All firewall rules will be simulated${NC}"
        echo -e "${PURPLE}   → Log file: $LOG_FILE${NC}"
        echo

        # Initialize mock environment if available (from external mock files)
        if declare -f mock_init_dry_run_environment >/dev/null 2>&1; then
            mock_init_dry_run_environment
        fi
    fi
}

# Check if running as root
check_sudo() {
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Running in dry-run mode (sudo check skipped)"
        return 0
    fi

    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo privileges"
        error "Usage: sudo $0"
        exit 1
    fi

    success "Running with administrative privileges"
}

# Check and install UFW if needed
check_ufw_installation() {
    print_section "UFW Installation Check"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "UFW installation check skipped in dry-run mode"
        return 0
    fi

    if ! command -v ufw >/dev/null 2>&1; then
        info "UFW not found, installing..."
        execute_command "apt update" "Update package repositories"
        execute_command "apt install -y ufw" "Install UFW firewall"
        success "UFW installed successfully"
    else
        success "UFW is already installed"
    fi
}

# Backup existing firewall configuration
backup_firewall_config() {
    print_section "Firewall Configuration Backup"

    execute_command "mkdir -p '$CONFIG_BACKUP_DIR'" "Create backup directory"

    # Backup UFW rules
    if [[ -f "/etc/ufw/user.rules" ]]; then
        execute_command "cp /etc/ufw/user.rules '$CONFIG_BACKUP_DIR/ufw-user.rules.backup'" "Backup UFW user rules"
    fi

    if [[ -f "/etc/ufw/user6.rules" ]]; then
        execute_command "cp /etc/ufw/user6.rules '$CONFIG_BACKUP_DIR/ufw-user6.rules.backup'" "Backup UFW IPv6 rules"
    fi

    # Backup iptables rules
    if command -v iptables-save >/dev/null 2>&1; then
        execute_command "iptables-save > '$CONFIG_BACKUP_DIR/iptables.backup'" "Backup iptables rules"
    fi

    # Backup fail2ban configuration
    if [[ -d "$FAIL2BAN_CONFIG_DIR" ]]; then
        execute_command "cp -r '$FAIL2BAN_CONFIG_DIR' '$CONFIG_BACKUP_DIR/fail2ban.backup'" "Backup fail2ban configuration"
    fi

    success "Firewall configuration backed up: $CONFIG_BACKUP_DIR"
}

# Configure UFW basic rules
configure_ufw_basic_rules() {
    print_section "UFW Basic Configuration"

    # Reset UFW to defaults
    execute_command "ufw --force reset" "Reset UFW to defaults"

    # Set default policies
    execute_command "ufw default deny incoming" "Set default incoming policy to deny"
    execute_command "ufw default allow outgoing" "Set default outgoing policy to allow"
    execute_command "ufw default deny forward" "Set default forward policy to deny"

    success "UFW basic rules configured"
}

# Configure SSH access rules
configure_ssh_rules() {
    print_section "SSH Access Rules"

    # Allow SSH on custom port
    execute_command "ufw allow $SSH_PORT/tcp comment 'SSH access on custom port'" "Allow SSH on port $SSH_PORT"

    # Rate limiting for SSH (brute force protection)
    execute_command "ufw limit $SSH_PORT/tcp comment 'SSH rate limiting'" "Enable SSH rate limiting"

    success "SSH firewall rules configured"
}

# Configure VPN access rules
configure_vpn_rules() {
    print_section "VPN Access Rules"

    # Allow WireGuard VPN
    execute_command "ufw allow $WIREGUARD_PORT/udp comment 'WireGuard VPN'" "Allow WireGuard on port $WIREGUARD_PORT"

    # Allow forwarding for VPN clients
    execute_command "ufw route allow in on wg0 out on eth0" "Allow VPN client forwarding to eth0"
    execute_command "ufw route allow in on eth0 out on wg0" "Allow return traffic from eth0 to VPN"

    # Allow VPN clients to access local services
    execute_command "ufw allow in on wg0 to any port 53 comment 'DNS for VPN clients'" "Allow DNS for VPN clients"
    execute_command "ufw allow in on wg0 to any port $SSH_PORT comment 'SSH for VPN clients'" "Allow SSH for VPN clients"

    success "VPN firewall rules configured"
}

# Configure remote desktop access rules
configure_remote_desktop_rules() {
    print_section "Remote Desktop Access Rules"

    # Allow VNC (restricted to VPN and local network)
    execute_command "ufw allow from 10.13.13.0/24 to any port $VNC_PORT comment 'VNC for VPN clients'" "Allow VNC for VPN clients"
    execute_command "ufw allow from 192.168.0.0/16 to any port $VNC_PORT comment 'VNC for local network'" "Allow VNC for local network"

    # Allow RDP (restricted to VPN and local network)
    execute_command "ufw allow from 10.13.13.0/24 to any port $RDP_PORT comment 'RDP for VPN clients'" "Allow RDP for VPN clients"
    execute_command "ufw allow from 192.168.0.0/16 to any port $RDP_PORT comment 'RDP for local network'" "Allow RDP for local network"

    success "Remote desktop firewall rules configured"
}

# Configure web services rules
configure_web_services_rules() {
    print_section "Web Services Rules"

    # Allow HTTP and HTTPS (for web interfaces and updates)
    execute_command "ufw allow out $HTTP_PORT/tcp comment 'HTTP outbound'" "Allow outbound HTTP"
    execute_command "ufw allow out $HTTPS_PORT/tcp comment 'HTTPS outbound'" "Allow outbound HTTPS"

    # Allow local web interfaces (Pi-hole, monitoring, etc.)
    execute_command "ufw allow from 10.13.13.0/24 to any port $HTTP_PORT comment 'HTTP for VPN clients'" "Allow HTTP for VPN clients"
    execute_command "ufw allow from 192.168.0.0/16 to any port $HTTP_PORT comment 'HTTP for local network'" "Allow HTTP for local network"

    success "Web services firewall rules configured"
}

# Configure advanced security rules
configure_advanced_security_rules() {
    print_section "Advanced Security Rules"

    # Block common attack patterns
    execute_command "ufw deny from 169.254.0.0/16 comment 'Block link-local addresses'" "Block link-local addresses"
    execute_command "ufw deny from 224.0.0.0/4 comment 'Block multicast addresses'" "Block multicast addresses"
    execute_command "ufw deny from 240.0.0.0/5 comment 'Block reserved addresses'" "Block reserved addresses"

    # Block invalid packets
    execute_command "ufw deny in quick on any from any to any with invalid" "Block invalid packets"

    # Log denied connections
    execute_command "ufw logging on" "Enable UFW logging"

    success "Advanced security rules configured"
}

# Configure fail2ban
configure_fail2ban() {
    print_section "Fail2ban Configuration"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "Fail2ban configuration skipped in dry-run mode"
        return 0
    fi

    # Check if fail2ban is installed
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        warning "Fail2ban not installed, installing..."
        execute_command "apt install -y fail2ban" "Install fail2ban"
    fi

    # Create fail2ban local configuration
    execute_command "cat > '$FAIL2BAN_LOCAL_CONFIG' << 'EOF'
# Pi Gateway Fail2ban Configuration
# Enhanced security with intrusion detection and prevention

[DEFAULT]
# Ban IP addresses for 1 hour (3600 seconds)
bantime = 3600

# Monitor for attacks over 10 minutes
findtime = 600

# Ban after 5 failed attempts
maxretry = 5

# Ignore local networks
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12

# Email notifications (configure if desired)
#destemail = admin@example.com
#sendername = Pi Gateway Fail2ban
#action = %(action_mwl)s

# Log level
loglevel = INFO

# Backend for log file monitoring
backend = auto

#=============================================================================
# SSH Protection
#=============================================================================

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

# Additional SSH protection for custom port
[sshd-custom]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 2
bantime = 7200
findtime = 300

#=============================================================================
# VPN Protection
#=============================================================================

[wireguard]
enabled = true
port = $WIREGUARD_PORT
protocol = udp
filter = wireguard
logpath = /var/log/syslog
maxretry = 3
bantime = 1800

#=============================================================================
# Web Services Protection
#=============================================================================

[apache-auth]
enabled = false
port = http,https
filter = apache-auth
logpath = /var/log/apache2/*error.log

[apache-badbots]
enabled = false
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/*access.log
bantime = 86400
maxretry = 1

[nginx-auth]
enabled = false
port = http,https
filter = nginx-auth
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = false
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6

#=============================================================================
# System Protection
#=============================================================================

[pam-generic]
enabled = true
filter = pam-generic
logpath = /var/log/auth.log
maxretry = 6
bantime = 600

[systemd-auth]
enabled = true
filter = systemd-auth
logpath = /var/log/auth.log
maxretry = 5
bantime = 1200

#=============================================================================
# Network Services Protection
#=============================================================================

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = iptables-allports[name=recidive]
bantime = 86400
findtime = 86400
maxretry = 3

[postfix]
enabled = false
port = smtp,465,submission
filter = postfix
logpath = /var/log/mail.log

[dovecot]
enabled = false
port = pop3,pop3s,imap,imaps,submission,465,sieve
filter = dovecot
logpath = /var/log/mail.log

#=============================================================================
# Custom Filters
#=============================================================================

# Add custom jails here for specific services
# Example for Pi-hole:
#[pihole]
#enabled = false
#port = http,https
#filter = pihole
#logpath = /var/log/pihole.log
#maxretry = 3
EOF" "Create fail2ban local configuration"

    # Create custom WireGuard filter
    execute_command "cat > '$FAIL2BAN_CONFIG_DIR/filter.d/wireguard.conf' << 'EOF'
# Fail2ban filter for WireGuard VPN
[Definition]
failregex = .*: Invalid handshake initiation from <HOST>.*
            .*: Handshake did not complete after .* seconds, retrying \(try .*\) \[<HOST>\].*
            .*: Packet with invalid message type .* from <HOST>.*

ignoreregex =
EOF" "Create WireGuard fail2ban filter"

    # Enable and start fail2ban
    execute_command "systemctl enable fail2ban" "Enable fail2ban service"
    execute_command "systemctl restart fail2ban" "Restart fail2ban service"

    success "Fail2ban configured and started"
}

# Enable UFW firewall
enable_ufw() {
    print_section "UFW Activation"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "UFW activation skipped in dry-run mode"
        return 0
    fi

    # Enable UFW (this will prompt for confirmation in normal mode)
    execute_command "ufw --force enable" "Enable UFW firewall"

    # Enable UFW service
    execute_command "systemctl enable ufw" "Enable UFW service on boot"

    # Check UFW status
    if ufw status | grep -q "Status: active"; then
        success "UFW firewall is active and enabled"
    else
        error "UFW failed to activate"
        exit 1
    fi
}

# Display firewall status and rules
display_firewall_status() {
    print_section "Firewall Status and Rules"

    echo
    echo -e "${GREEN}🔥 Firewall Setup Complete!${NC}"
    echo

    if [[ "$DRY_RUN" == "false" ]]; then
        echo -e "${BLUE}UFW Status:${NC}"
        ufw status verbose || echo "  UFW status not available"
        echo

        echo -e "${BLUE}Fail2ban Status:${NC}"
        fail2ban-client status 2>/dev/null || echo "  Fail2ban status not available"
        echo
    fi

    echo -e "${BLUE}Firewall Configuration Summary:${NC}"
    echo -e "  ${YELLOW}SSH Port:${NC} $SSH_PORT (with rate limiting)"
    echo -e "  ${YELLOW}VPN Port:${NC} $WIREGUARD_PORT (WireGuard)"
    echo -e "  ${YELLOW}Remote Desktop:${NC} Restricted to VPN and local network"
    echo -e "  ${YELLOW}Web Services:${NC} Outbound allowed, inbound restricted"
    echo -e "  ${YELLOW}Intrusion Detection:${NC} Fail2ban active"
    echo

    echo -e "${BLUE}Security Features Enabled:${NC}"
    echo -e "  • SSH brute force protection"
    echo -e "  • VPN connection monitoring"
    echo -e "  • Invalid packet blocking"
    echo -e "  • Attack pattern detection"
    echo -e "  • Automatic IP banning"
    echo -e "  • Connection logging"
    echo

    echo -e "${BLUE}Management Commands:${NC}"
    echo -e "  ${PURPLE}Check status:${NC} sudo ufw status verbose"
    echo -e "  ${PURPLE}Add rule:${NC} sudo ufw allow <port>"
    echo -e "  ${PURPLE}Remove rule:${NC} sudo ufw delete <rule>"
    echo -e "  ${PURPLE}Fail2ban status:${NC} sudo fail2ban-client status"
    echo -e "  ${PURPLE}Check banned IPs:${NC} sudo fail2ban-client status sshd"
    echo

    echo -e "${YELLOW}⚠️  Important Security Notes:${NC}"
    echo -e "  • Firewall is configured for Pi Gateway services"
    echo -e "  • SSH is protected with rate limiting and fail2ban"
    echo -e "  • Remote access is restricted to VPN and local network"
    echo -e "  • Monitor logs regularly: /var/log/ufw.log"
    echo -e "  • Review fail2ban logs: /var/log/fail2ban.log"
    echo

    success "Firewall setup completed successfully!"
}

# Main execution
main() {
    print_header

    log "INFO" "Starting Pi Gateway firewall setup"

    # Initialize dry-run environment
    init_dry_run_environment

    # Pre-setup checks
    check_sudo
    check_ufw_installation

    # Setup process
    backup_firewall_config
    configure_ufw_basic_rules
    configure_ssh_rules
    configure_vpn_rules
    configure_remote_desktop_rules
    configure_web_services_rules
    configure_advanced_security_rules
    configure_fail2ban
    enable_ufw

    # Final information
    display_firewall_status

    log "INFO" "Pi Gateway firewall setup completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi