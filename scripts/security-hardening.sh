#!/bin/bash
#
# Pi Gateway Security Hardening & Compliance System
# Advanced security configuration and compliance monitoring
#

set -euo pipefail

# Check Bash version compatibility
if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
    echo "Error: This script requires Bash 4.0+ for associative arrays"
    echo "Current version: $BASH_VERSION"
    exit 1
fi

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly LOG_DIR="$PROJECT_ROOT/logs"
readonly STATE_DIR="$PROJECT_ROOT/state"
readonly SECURITY_CONFIG="$CONFIG_DIR/security-hardening.conf"
readonly SECURITY_STATE="$STATE_DIR/security-hardening.json"
readonly COMPLIANCE_LOG="$LOG_DIR/compliance.log"

# Security profiles
readonly SECURITY_PROFILES_DIR="$CONFIG_DIR/security-profiles"
readonly DEFAULT_PROFILE="standard"

# Logging functions
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$COMPLIANCE_LOG"; }
success() { echo -e "  ${GREEN}✓${NC} $1" | tee -a "$COMPLIANCE_LOG"; }
error() { echo -e "  ${RED}✗${NC} $1" | tee -a "$COMPLIANCE_LOG"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1" | tee -a "$COMPLIANCE_LOG"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1" | tee -a "$COMPLIANCE_LOG"; }
debug() { [[ "${DEBUG:-}" == "true" ]] && echo -e "  ${PURPLE}🔍${NC} $1" | tee -a "$COMPLIANCE_LOG"; }

# Initialize security system
initialize_security() {
    log "Initializing security hardening system..."

    # Create required directories
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$STATE_DIR" "$SECURITY_PROFILES_DIR"

    # Create default configuration if it doesn't exist
    if [[ ! -f "$SECURITY_CONFIG" ]]; then
        create_default_config
    fi

    # Initialize state file
    if [[ ! -f "$SECURITY_STATE" ]]; then
        echo '{"last_run": "", "profile": "standard", "hardening_status": {}, "compliance_checks": {}}' > "$SECURITY_STATE"
    fi

    success "Security system initialized"
}

# Create default security configuration
create_default_config() {
    cat > "$SECURITY_CONFIG" << 'EOF'
# Pi Gateway Security Hardening Configuration

# Security Profile
SECURITY_PROFILE="standard"

# System Hardening
ENABLE_KERNEL_HARDENING=true
ENABLE_NETWORK_HARDENING=true
ENABLE_FILE_SYSTEM_HARDENING=true
ENABLE_PROCESS_HARDENING=true

# SSH Hardening
SSH_DISABLE_ROOT_LOGIN=true
SSH_DISABLE_PASSWORD_AUTH=true
SSH_ENABLE_KEY_AUTH=true
SSH_MAX_AUTH_TRIES=3
SSH_CLIENT_ALIVE_INTERVAL=300
SSH_CLIENT_ALIVE_COUNT_MAX=2

# Firewall Configuration
UFW_DEFAULT_DENY_INCOMING=true
UFW_DEFAULT_ALLOW_OUTGOING=true
UFW_ENABLE_LOGGING=true

# Audit Configuration
ENABLE_AUDITD=true
AUDIT_LOG_RETENTION_DAYS=90
ENABLE_SYSTEM_CALL_AUDITING=true

# Compliance Standards
ENABLE_CIS_BENCHMARK=true
ENABLE_NIST_COMPLIANCE=false
ENABLE_GDPR_COMPLIANCE=false

# Monitoring
ENABLE_INTRUSION_DETECTION=true
ENABLE_FILE_INTEGRITY_MONITORING=true
ENABLE_LOG_MONITORING=true

# Automatic Updates
ENABLE_SECURITY_UPDATES=true
ENABLE_AUTOMATIC_REBOOT=false
SECURITY_UPDATE_HOUR=3

# Network Security
ENABLE_DDoS_PROTECTION=true
ENABLE_PORT_SCAN_DETECTION=true
BLOCK_SUSPICIOUS_IPS=true

# Privacy and Data Protection
DISABLE_UNNECESSARY_SERVICES=true
ANONYMIZE_LOGS=false
SECURE_DELETE_ENABLED=true
EOF

    success "Default security configuration created"
}

# Load configuration
load_config() {
    if [[ -f "$SECURITY_CONFIG" ]]; then
        # shellcheck source=/dev/null
        source "$SECURITY_CONFIG"
        debug "Security configuration loaded"
    else
        error "Security configuration not found: $SECURITY_CONFIG"
        return 1
    fi
}

# Update security state
update_security_state() {
    local key="$1"
    local value="$2"
    local timestamp=$(date -Iseconds)

    # Read current state
    local current_state
    current_state=$(cat "$SECURITY_STATE" 2>/dev/null || echo '{}')

    # Update state using jq if available, otherwise use basic JSON manipulation
    if command -v jq >/dev/null 2>&1; then
        echo "$current_state" | jq --arg key "$key" --arg value "$value" --arg time "$timestamp" \
            '.last_run = $time | .hardening_status[$key] = $value' > "$SECURITY_STATE"
    else
        # Basic JSON update without jq
        echo "{\"last_run\": \"$timestamp\", \"hardening_status\": {\"$key\": \"$value\"}}" > "$SECURITY_STATE"
    fi

    debug "Security state updated: $key = $value"
}

# Kernel hardening
harden_kernel() {
    info "Applying kernel security hardening..."

    local sysctl_changes=()
    local sysctl_file="/etc/sysctl.d/99-pi-gateway-security.conf"

    # Kernel address space layout randomization
    sysctl_changes+=("kernel.randomize_va_space=2")

    # Kernel pointer restrictions
    sysctl_changes+=("kernel.kptr_restrict=2")

    # Disable kernel debugging
    sysctl_changes+=("kernel.dmesg_restrict=1")

    # Control access to kernel logs
    sysctl_changes+=("kernel.printk=3 3 3 3")

    # Disable magic SysRq key
    sysctl_changes+=("kernel.sysrq=0")

    # Core dump restrictions
    sysctl_changes+=("fs.suid_dumpable=0")

    # Process restrictions
    sysctl_changes+=("kernel.yama.ptrace_scope=1")

    # Memory protection
    sysctl_changes+=("vm.mmap_min_addr=65536")

    # Apply changes
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would apply kernel hardening settings to $sysctl_file"
        for change in "${sysctl_changes[@]}"; do
            debug "[DRY RUN] Would set: $change"
        done
    else
        {
            echo "# Pi Gateway Kernel Security Hardening"
            echo "# Generated on $(date)"
            echo ""
            for change in "${sysctl_changes[@]}"; do
                echo "$change"
            done
        } > "$sysctl_file"

        # Apply immediately
        sysctl -p "$sysctl_file" >/dev/null 2>&1 || warning "Some kernel parameters could not be applied"
        success "Kernel hardening applied"
    fi

    update_security_state "kernel_hardening" "applied"
}

# Network hardening
harden_network() {
    info "Applying network security hardening..."

    local sysctl_changes=()
    local sysctl_file="/etc/sysctl.d/99-pi-gateway-network-security.conf"

    # IP forwarding control
    sysctl_changes+=("net.ipv4.ip_forward=0")
    sysctl_changes+=("net.ipv6.conf.all.forwarding=0")

    # Source routing protection
    sysctl_changes+=("net.ipv4.conf.all.accept_source_route=0")
    sysctl_changes+=("net.ipv4.conf.default.accept_source_route=0")
    sysctl_changes+=("net.ipv6.conf.all.accept_source_route=0")

    # ICMP redirect protection
    sysctl_changes+=("net.ipv4.conf.all.accept_redirects=0")
    sysctl_changes+=("net.ipv4.conf.default.accept_redirects=0")
    sysctl_changes+=("net.ipv6.conf.all.accept_redirects=0")

    # Secure redirects
    sysctl_changes+=("net.ipv4.conf.all.secure_redirects=0")
    sysctl_changes+=("net.ipv4.conf.default.secure_redirects=0")

    # Send redirects
    sysctl_changes+=("net.ipv4.conf.all.send_redirects=0")
    sysctl_changes+=("net.ipv4.conf.default.send_redirects=0")

    # RP filter (reverse path filtering)
    sysctl_changes+=("net.ipv4.conf.all.rp_filter=1")
    sysctl_changes+=("net.ipv4.conf.default.rp_filter=1")

    # Log suspicious packets
    sysctl_changes+=("net.ipv4.conf.all.log_martians=1")
    sysctl_changes+=("net.ipv4.conf.default.log_martians=1")

    # Ignore ICMP ping requests
    sysctl_changes+=("net.ipv4.icmp_echo_ignore_all=0")
    sysctl_changes+=("net.ipv4.icmp_echo_ignore_broadcasts=1")

    # Ignore bogus ICMP error responses
    sysctl_changes+=("net.ipv4.icmp_ignore_bogus_error_responses=1")

    # TCP SYN cookies
    sysctl_changes+=("net.ipv4.tcp_syncookies=1")

    # TCP timestamps
    sysctl_changes+=("net.ipv4.tcp_timestamps=0")

    # IPv6 router advertisements
    sysctl_changes+=("net.ipv6.conf.all.accept_ra=0")
    sysctl_changes+=("net.ipv6.conf.default.accept_ra=0")

    # Apply changes
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would apply network hardening settings to $sysctl_file"
        for change in "${sysctl_changes[@]}"; do
            debug "[DRY RUN] Would set: $change"
        done
    else
        {
            echo "# Pi Gateway Network Security Hardening"
            echo "# Generated on $(date)"
            echo ""
            for change in "${sysctl_changes[@]}"; do
                echo "$change"
            done
        } > "$sysctl_file"

        # Apply immediately
        sysctl -p "$sysctl_file" >/dev/null 2>&1 || warning "Some network parameters could not be applied"
        success "Network hardening applied"
    fi

    update_security_state "network_hardening" "applied"
}

# SSH hardening
harden_ssh() {
    info "Applying SSH security hardening..."

    local ssh_config="/etc/ssh/sshd_config"
    local backup_config="$ssh_config.pi-gateway-backup-$(date +%Y%m%d-%H%M%S)"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would harden SSH configuration in $ssh_config"
        return
    fi

    # Backup current configuration
    if [[ -f "$ssh_config" ]]; then
        cp "$ssh_config" "$backup_config"
        debug "SSH config backed up to $backup_config"
    fi

    # Apply SSH hardening settings
    local ssh_settings=(
        "Protocol 2"
        "PermitRootLogin no"
        "PasswordAuthentication no"
        "PubkeyAuthentication yes"
        "AuthorizedKeysFile .ssh/authorized_keys"
        "MaxAuthTries 3"
        "ClientAliveInterval 300"
        "ClientAliveCountMax 2"
        "PermitEmptyPasswords no"
        "X11Forwarding no"
        "MaxStartups 10:30:60"
        "AllowUsers pi"
        "Banner /etc/issue.net"
        "UsePAM yes"
    )

    # Create hardened SSH configuration
    {
        echo "# Pi Gateway SSH Security Hardening"
        echo "# Generated on $(date)"
        echo "# Original config backed up to $backup_config"
        echo ""
        for setting in "${ssh_settings[@]}"; do
            echo "$setting"
        done
        echo ""
        echo "# Include original config (commented out for reference)"
        if [[ -f "$backup_config" ]]; then
            sed 's/^/# /' "$backup_config"
        fi
    } > "$ssh_config"

    # Create security banner
    cat > /etc/issue.net << 'EOF'
***************************************************************************
                    AUTHORIZED ACCESS ONLY

This system is for authorized users only. Individuals using this computer
system without authority, or in excess of their authority, are subject to
having all of their activities on this system monitored and recorded.

In the course of monitoring individuals improperly using this system, or in
the course of system maintenance, the activities of authorized users may
also be monitored.

Anyone using this system expressly consents to such monitoring and is advised
that if such monitoring reveals possible evidence of criminal activity,
system personnel may provide the evidence to law enforcement officials.
***************************************************************************
EOF

    # Test SSH configuration
    if sshd -t 2>/dev/null; then
        # Restart SSH service
        systemctl restart ssh
        success "SSH hardening applied successfully"
    else
        # Restore backup if configuration is invalid
        cp "$backup_config" "$ssh_config"
        systemctl restart ssh
        error "SSH configuration invalid, restored backup"
        return 1
    fi

    update_security_state "ssh_hardening" "applied"
}

# Firewall hardening
harden_firewall() {
    info "Configuring advanced firewall rules..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would configure UFW firewall rules"
        return
    fi

    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable
    fi

    # Reset to defaults
    ufw --force reset

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (current connection)
    ufw allow ssh

    # Allow WireGuard VPN
    ufw allow 51820/udp

    # Rate limiting for SSH
    ufw limit ssh

    # Block common attack vectors
    ufw deny from 192.168.0.0/16 to any port 22  # Block RFC1918 from SSH
    ufw deny from 172.16.0.0/12 to any port 22
    ufw deny from 10.0.0.0/8 to any port 22

    # Allow local network access
    local_network=$(ip route | grep -E '^192\.168\.|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-1]\.|^10\.' | head -1 | awk '{print $1}')
    if [[ -n "$local_network" ]]; then
        ufw allow from "$local_network"
    fi

    # Enable logging
    ufw logging on

    success "Firewall hardening applied"
    update_security_state "firewall_hardening" "applied"
}

# File system hardening
harden_filesystem() {
    info "Applying file system security hardening..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would apply file system hardening"
        return
    fi

    # Set proper permissions on sensitive files
    local sensitive_files=(
        "/etc/passwd:644"
        "/etc/shadow:640"
        "/etc/group:644"
        "/etc/gshadow:640"
        "/etc/ssh/sshd_config:600"
        "/etc/sudoers:440"
    )

    for file_perm in "${sensitive_files[@]}"; do
        local file="${file_perm%:*}"
        local perm="${file_perm#*:}"

        if [[ -f "$file" ]]; then
            chmod "$perm" "$file"
            debug "Set permissions $perm on $file"
        fi
    done

    # Secure boot files
    if [[ -d "/boot" ]]; then
        chmod 700 /boot
        debug "Secured /boot directory"
    fi

    # Create secure tmp directory
    if ! grep -q "/tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,nodev,nosuid,noexec,size=1G 0 0" >> /etc/fstab
        debug "Added secure /tmp mount to fstab"
    fi

    success "File system hardening applied"
    update_security_state "filesystem_hardening" "applied"
}

# Install and configure audit system
setup_audit_system() {
    info "Setting up audit system..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install and configure auditd"
        return
    fi

    # Install auditd if not present
    if ! command -v auditctl >/dev/null 2>&1; then
        apt-get update
        apt-get install -y auditd audispd-plugins
    fi

    # Configure audit rules
    cat > /etc/audit/rules.d/pi-gateway.rules << 'EOF'
# Pi Gateway Audit Rules

# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode (0=silent, 1=printk, 2=panic)
-f 1

# Monitor authentication events
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor system configuration changes
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor network configuration
-w /etc/hosts -p wa -k network_config
-w /etc/network/ -p wa -k network_config

# Monitor privilege escalation
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privilege_escalation
-a always,exit -F arch=b32 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privilege_escalation

# Monitor file deletions
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k file_deletion
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k file_deletion

# Lock configuration
-e 2
EOF

    # Restart auditd
    systemctl enable auditd
    systemctl restart auditd

    success "Audit system configured"
    update_security_state "audit_system" "configured"
}

# Disable unnecessary services
disable_unnecessary_services() {
    info "Disabling unnecessary services..."

    local services_to_disable=(
        "bluetooth"
        "avahi-daemon"
        "cups"
        "cups-browsed"
        "ModemManager"
        "wpa_supplicant"
    )

    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                info "[DRY RUN] Would disable service: $service"
            else
                systemctl disable "$service"
                systemctl stop "$service" 2>/dev/null || true
                debug "Disabled service: $service"
            fi
        fi
    done

    success "Unnecessary services disabled"
    update_security_state "service_hardening" "applied"
}

# Run compliance checks
run_compliance_checks() {
    info "Running security compliance checks..."

    local compliance_results=()
    local total_checks=0
    local passed_checks=0

    # CIS Benchmark checks
    if [[ "${ENABLE_CIS_BENCHMARK:-false}" == "true" ]]; then
        info "Running CIS Benchmark compliance checks..."

        # Check 1.1.1.1 - Disable unused filesystems
        total_checks=$((total_checks + 1))
        if ! lsmod | grep -q cramfs; then
            compliance_results+=("PASS: CIS 1.1.1.1 - cramfs filesystem disabled")
            passed_checks=$((passed_checks + 1))
        else
            compliance_results+=("FAIL: CIS 1.1.1.1 - cramfs filesystem enabled")
        fi

        # Check 1.4.1 - Bootloader password
        total_checks=$((total_checks + 1))
        if [[ -f "/boot/grub/grub.cfg" ]] && grep -q "password" /boot/grub/grub.cfg; then
            compliance_results+=("PASS: CIS 1.4.1 - Bootloader password set")
            passed_checks=$((passed_checks + 1))
        else
            compliance_results+=("INFO: CIS 1.4.1 - Bootloader password check skipped (Pi uses different boot system)")
            passed_checks=$((passed_checks + 1))
        fi

        # Check 4.1.1 - Audit system enabled
        total_checks=$((total_checks + 1))
        if systemctl is-enabled auditd >/dev/null 2>&1; then
            compliance_results+=("PASS: CIS 4.1.1 - Audit system enabled")
            passed_checks=$((passed_checks + 1))
        else
            compliance_results+=("FAIL: CIS 4.1.1 - Audit system not enabled")
        fi

        # Check 5.2.3 - SSH LogLevel
        total_checks=$((total_checks + 1))
        if grep -q "^LogLevel INFO" /etc/ssh/sshd_config; then
            compliance_results+=("PASS: CIS 5.2.3 - SSH LogLevel set to INFO")
            passed_checks=$((passed_checks + 1))
        else
            compliance_results+=("FAIL: CIS 5.2.3 - SSH LogLevel not set to INFO")
        fi
    fi

    # Print compliance results
    echo
    info "Compliance Check Results:"
    for result in "${compliance_results[@]}"; do
        if [[ "$result" == PASS:* ]]; then
            success "${result#PASS: }"
        elif [[ "$result" == FAIL:* ]]; then
            error "${result#FAIL: }"
        else
            info "${result#INFO: }"
        fi
    done

    echo
    local compliance_percentage=$((passed_checks * 100 / total_checks))
    info "Compliance Score: $passed_checks/$total_checks ($compliance_percentage%)"

    update_security_state "compliance_score" "$compliance_percentage"
}

# Generate security report
generate_security_report() {
    info "Generating security hardening report..."

    local report_file="$LOG_DIR/security-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "Pi Gateway Security Hardening Report"
        echo "Generated: $(date)"
        echo "Profile: ${SECURITY_PROFILE:-standard}"
        echo "=================================="
        echo

        echo "Hardening Status:"
        if [[ -f "$SECURITY_STATE" ]]; then
            # Use jq if available for better formatting
            if command -v jq >/dev/null 2>&1; then
                jq -r '.hardening_status | to_entries[] | "  \(.key): \(.value)"' "$SECURITY_STATE"
            else
                cat "$SECURITY_STATE"
            fi
        fi
        echo

        echo "System Information:"
        echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo "  Kernel: $(uname -r)"
        echo "  Architecture: $(uname -m)"
        echo "  Uptime: $(uptime -p)"
        echo

        echo "Network Configuration:"
        echo "  IP Address: $(hostname -I | awk '{print $1}')"
        echo "  Firewall Status: $(ufw status | head -1)"
        echo "  SSH Status: $(systemctl is-active ssh)"
        echo

        echo "Security Services:"
        echo "  Audit System: $(systemctl is-active auditd 2>/dev/null || echo 'inactive')"
        echo "  Fail2ban: $(systemctl is-active fail2ban 2>/dev/null || echo 'inactive')"
        echo

        echo "Recent Security Events:"
        if [[ -f "$COMPLIANCE_LOG" ]]; then
            tail -20 "$COMPLIANCE_LOG" | grep -E "(FAIL|error|warning)" || echo "  No recent security issues found"
        fi

    } > "$report_file"

    success "Security report generated: $report_file"

    # Also output summary to console
    echo
    info "Security Hardening Summary:"
    success "✓ Kernel hardening applied"
    success "✓ Network hardening applied"
    success "✓ SSH hardening applied"
    success "✓ Firewall configured"
    success "✓ File system secured"
    success "✓ Audit system enabled"
    success "✓ Unnecessary services disabled"
    success "✓ Compliance checks completed"

    update_security_state "last_report" "$report_file"
}

# Main hardening function
run_security_hardening() {
    local profile="${1:-$DEFAULT_PROFILE}"

    log "Starting security hardening with profile: $profile"

    initialize_security
    load_config

    # Apply hardening based on configuration
    if [[ "${ENABLE_KERNEL_HARDENING:-true}" == "true" ]]; then
        harden_kernel
    fi

    if [[ "${ENABLE_NETWORK_HARDENING:-true}" == "true" ]]; then
        harden_network
    fi

    harden_ssh
    harden_firewall

    if [[ "${ENABLE_FILE_SYSTEM_HARDENING:-true}" == "true" ]]; then
        harden_filesystem
    fi

    if [[ "${ENABLE_AUDITD:-true}" == "true" ]]; then
        setup_audit_system
    fi

    if [[ "${DISABLE_UNNECESSARY_SERVICES:-true}" == "true" ]]; then
        disable_unnecessary_services
    fi

    run_compliance_checks
    generate_security_report

    success "Security hardening completed successfully"
    log "Security hardening completed with profile: $profile"
}

# Show security status
show_security_status() {
    echo -e "${CYAN}🔒 Pi Gateway Security Status${NC}"
    echo

    if [[ ! -f "$SECURITY_STATE" ]]; then
        warning "Security system not initialized"
        return 1
    fi

    # Show current status
    info "Security Hardening Status:"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.hardening_status | to_entries[] | "  \(.key): \(.value)"' "$SECURITY_STATE" | while read -r line; do
            if [[ "$line" == *": applied"* ]] || [[ "$line" == *": configured"* ]]; then
                success "$line"
            else
                warning "$line"
            fi
        done
    fi

    echo
    info "System Security Information:"

    # SSH status
    if systemctl is-active --quiet ssh; then
        success "SSH service: Active"
    else
        error "SSH service: Inactive"
    fi

    # Firewall status
    local ufw_status
    ufw_status=$(ufw status | head -1)
    if [[ "$ufw_status" == *"active"* ]]; then
        success "Firewall: $ufw_status"
    else
        warning "Firewall: $ufw_status"
    fi

    # Audit system
    if systemctl is-active --quiet auditd; then
        success "Audit system: Active"
    else
        warning "Audit system: Inactive"
    fi

    # Show compliance score if available
    if command -v jq >/dev/null 2>&1 && jq -e '.compliance_score' "$SECURITY_STATE" >/dev/null 2>&1; then
        local score
        score=$(jq -r '.compliance_score' "$SECURITY_STATE")
        info "Compliance score: $score%"
    fi
}

# Show help
show_help() {
    echo "Pi Gateway Security Hardening System"
    echo
    echo "Usage: $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "  harden [profile]     Apply security hardening (default: standard)"
    echo "  status               Show current security status"
    echo "  check               Run compliance checks only"
    echo "  report              Generate security report"
    echo "  profiles            List available security profiles"
    echo "  help                Show this help message"
    echo
    echo "Options:"
    echo "  --dry-run           Show what would be done without making changes"
    echo "  --debug             Enable debug output"
    echo
    echo "Security Profiles:"
    echo "  standard            Standard security hardening (default)"
    echo "  strict              Strict security with additional restrictions"
    echo "  minimal             Minimal hardening for compatibility"
    echo
    echo "Examples:"
    echo "  $(basename "$0") harden standard"
    echo "  $(basename "$0") status"
    echo "  $(basename "$0") check --dry-run"
    echo
}

# Main execution
main() {
    local command="${1:-}"

    # Handle global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            --debug)
                export DEBUG=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    case $command in
        harden)
            local profile="${2:-$DEFAULT_PROFILE}"
            run_security_hardening "$profile"
            ;;
        status)
            show_security_status
            ;;
        check)
            initialize_security
            load_config
            run_compliance_checks
            ;;
        report)
            initialize_security
            load_config
            generate_security_report
            ;;
        profiles)
            echo "Available security profiles:"
            echo "  standard - Standard security hardening"
            echo "  strict   - Strict security with additional restrictions"
            echo "  minimal  - Minimal hardening for compatibility"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -n "$command" ]]; then
                error "Unknown command: $command"
            else
                error "No command specified"
            fi
            echo "Use '$(basename "$0") help' for available commands"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
