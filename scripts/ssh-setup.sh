#!/bin/bash
#
# Pi Gateway - SSH Hardening & Configuration
# Secure SSH setup with key-based authentication and security hardening
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
readonly LOG_FILE="/tmp/pi-gateway-ssh-setup.log"
readonly CONFIG_BACKUP_DIR="/etc/pi-gateway/backups/ssh-$(date +%Y%m%d_%H%M%S)"
readonly SSH_CONFIG="/etc/ssh/sshd_config"
readonly SSH_USER_CONFIG="/home/pi/.ssh/config"
readonly DEFAULT_SSH_PORT=2222
readonly SSH_KEY_TYPE="ed25519"
readonly SSH_KEY_BITS=4096

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
    echo -e "${BLUE}       Pi Gateway - SSH Hardening Setup       ${NC}"
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
        echo -e "${PURPLE}   → No actual system changes will be made${NC}"
        echo -e "${PURPLE}   → All SSH configuration will be simulated${NC}"
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

# Backup existing SSH configuration
backup_ssh_config() {
    print_section "Configuration Backup"

    execute_command "mkdir -p '$CONFIG_BACKUP_DIR'" "Create backup directory"

    if [[ -f "$SSH_CONFIG" ]]; then
        execute_command "cp '$SSH_CONFIG' '$CONFIG_BACKUP_DIR/sshd_config.backup'" "Backup SSH daemon config"
        success "SSH daemon configuration backed up"
    else
        warning "SSH daemon config not found (fresh installation)"
    fi

    if [[ -f "$SSH_USER_CONFIG" ]]; then
        execute_command "cp '$SSH_USER_CONFIG' '$CONFIG_BACKUP_DIR/ssh_config.backup'" "Backup SSH client config"
        success "SSH client configuration backed up"
    fi

    success "Configuration backup completed: $CONFIG_BACKUP_DIR"
}

# Generate SSH host keys with strong algorithms
generate_host_keys() {
    print_section "SSH Host Key Generation"

    local key_types=("rsa" "ed25519" "ecdsa")
    local ssh_dir="/etc/ssh"

    for key_type in "${key_types[@]}"; do
        local key_file="$ssh_dir/ssh_host_${key_type}_key"

        if [[ "$key_type" == "rsa" ]]; then
            execute_command "ssh-keygen -t rsa -b 4096 -f '$key_file' -N '' -C 'Pi Gateway SSH Host Key (RSA)'" "Generate RSA host key"
        elif [[ "$key_type" == "ed25519" ]]; then
            execute_command "ssh-keygen -t ed25519 -f '$key_file' -N '' -C 'Pi Gateway SSH Host Key (Ed25519)'" "Generate Ed25519 host key"
        elif [[ "$key_type" == "ecdsa" ]]; then
            execute_command "ssh-keygen -t ecdsa -b 521 -f '$key_file' -N '' -C 'Pi Gateway SSH Host Key (ECDSA)'" "Generate ECDSA host key"
        fi

        # Set proper permissions
        execute_command "chmod 600 '$key_file'" "Set private key permissions"
        execute_command "chmod 644 '${key_file}.pub'" "Set public key permissions"

        success "Generated $key_type host key"
    done

    success "All SSH host keys generated successfully"
}

# Generate SSH key pair for pi user
generate_user_keys() {
    print_section "User SSH Key Generation"

    local pi_ssh_dir="/home/pi/.ssh"
    local key_file="$pi_ssh_dir/id_$SSH_KEY_TYPE"

    execute_command "mkdir -p '$pi_ssh_dir'" "Create SSH directory for pi user"
    execute_command "chown pi:pi '$pi_ssh_dir'" "Set SSH directory ownership"
    execute_command "chmod 700 '$pi_ssh_dir'" "Set SSH directory permissions"

    if [[ ! -f "$key_file" ]] || [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$SSH_KEY_TYPE" == "ed25519" ]]; then
            execute_command "ssh-keygen -t ed25519 -f '$key_file' -N '' -C 'pi@pi-gateway'" "Generate Ed25519 user key"
        else
            execute_command "ssh-keygen -t rsa -b $SSH_KEY_BITS -f '$key_file' -N '' -C 'pi@pi-gateway'" "Generate RSA user key"
        fi

        execute_command "chown pi:pi '$key_file' '${key_file}.pub'" "Set user key ownership"
        execute_command "chmod 600 '$key_file'" "Set private key permissions"
        execute_command "chmod 644 '${key_file}.pub'" "Set public key permissions"

        success "Generated SSH key pair for pi user"

        # Add public key to authorized_keys
        local authorized_keys="$pi_ssh_dir/authorized_keys"
        execute_command "cp '${key_file}.pub' '$authorized_keys'" "Add key to authorized_keys"
        execute_command "chown pi:pi '$authorized_keys'" "Set authorized_keys ownership"
        execute_command "chmod 600 '$authorized_keys'" "Set authorized_keys permissions"

        success "Public key added to authorized_keys"
    else
        info "SSH key pair already exists for pi user"
    fi
}

# Configure SSH daemon with security hardening
configure_sshd() {
    print_section "SSH Daemon Configuration"

    local temp_config="/tmp/sshd_config.tmp"

    # Create hardened SSH configuration
    execute_command "cat > '$temp_config' << 'EOF'
# Pi Gateway SSH Configuration - Security Hardened
# Generated on $(date)

# Network and Protocol Settings
Port $DEFAULT_SSH_PORT
Protocol 2
AddressFamily any
ListenAddress 0.0.0.0

# Host Key Settings
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_ecdsa_key

# Key Exchange and Cipher Settings
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

# Authentication Settings
LoginGraceTime 30
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 2
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Connection Settings
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive no
Compression no

# Forwarding and Tunneling
AllowAgentForwarding no
AllowTcpForwarding no
GatewayPorts no
X11Forwarding no
X11DisplayOffset 10
X11UseLocalhost yes
PermitTTY yes

# User and Access Control
AllowUsers pi
DenyUsers root
MaxStartups 2:30:5

# Logging
SyslogFacility AUTH
LogLevel VERBOSE

# Banner and Messages
Banner /etc/ssh/ssh_banner
PrintMotd no
PrintLastLog yes

# Subsystems
Subsystem sftp internal-sftp
EOF" "Create hardened SSH configuration"

    # Install the new configuration
    execute_command "mv '$temp_config' '$SSH_CONFIG'" "Install SSH daemon configuration"
    execute_command "chmod 644 '$SSH_CONFIG'" "Set SSH config permissions"

    success "SSH daemon configured with security hardening"
}

# Create SSH banner
create_ssh_banner() {
    print_section "SSH Banner Setup"

    local banner_file="/etc/ssh/ssh_banner"

    execute_command "cat > '$banner_file' << 'EOF'
┌─────────────────────────────────────────────────────────────┐
│                     Pi Gateway Access                       │
│                                                             │
│  🔒 This system is for authorized users only               │
│  🔍 All connections are monitored and logged               │
│  ⚠️  Unauthorized access is prohibited                      │
│                                                             │
│  Pi Gateway - Secure Homelab Bootstrap                     │
└─────────────────────────────────────────────────────────────┘
EOF" "Create SSH login banner"

    execute_command "chmod 644 '$banner_file'" "Set banner file permissions"
    success "SSH banner created"
}

# Configure SSH client settings
configure_ssh_client() {
    print_section "SSH Client Configuration"

    local client_config="/home/pi/.ssh/config"

    execute_command "cat > '$client_config' << 'EOF'
# Pi Gateway SSH Client Configuration
# Generated on $(date)

# Global settings
Host *
    Protocol 2
    ForwardAgent no
    ForwardX11 no
    HashKnownHosts yes
    CheckHostIP yes
    AddressFamily any
    ConnectTimeout 30
    ServerAliveInterval 60
    ServerAliveCountMax 3

    # Preferred authentication methods
    PreferredAuthentications publickey,keyboard-interactive,password

    # Key algorithms
    PubkeyAcceptedKeyTypes ssh-ed25519,rsa-sha2-512,rsa-sha2-256,ssh-rsa

    # Host key algorithms
    HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256,ssh-rsa

# Pi Gateway host entry
Host pi-gateway
    HostName localhost
    Port $DEFAULT_SSH_PORT
    User pi
    IdentityFile ~/.ssh/id_$SSH_KEY_TYPE
    StrictHostKeyChecking ask
EOF" "Create SSH client configuration"

    execute_command "chown pi:pi '$client_config'" "Set client config ownership"
    execute_command "chmod 644 '$client_config'" "Set client config permissions"

    success "SSH client configured"
}

# Test SSH configuration
test_ssh_config() {
    print_section "SSH Configuration Validation"

    # Test SSH daemon configuration
    if command -v sshd >/dev/null 2>&1; then
        execute_command "sshd -t" "Test SSH daemon configuration"
        success "SSH daemon configuration is valid"
    else
        warning "SSH daemon not available for testing"
    fi

    # Check SSH service status
    if command -v systemctl >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" ]]; then
            success "SSH service status check skipped in dry-run mode"
        else
            if systemctl is-active ssh >/dev/null 2>&1; then
                success "SSH service is running"
            else
                warning "SSH service is not running - will be started after configuration"
            fi
        fi
    fi
}

# Restart SSH service
restart_ssh_service() {
    print_section "SSH Service Management"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "SSH service restart skipped in dry-run mode"
        return 0
    fi

    # Restart SSH service
    execute_command "systemctl restart ssh" "Restart SSH service"
    success "SSH service restarted"

    # Enable SSH service
    execute_command "systemctl enable ssh" "Enable SSH service on boot"
    success "SSH service enabled for automatic startup"

    # Verify service is running
    sleep 2
    if systemctl is-active ssh >/dev/null 2>&1; then
        success "SSH service is running successfully"
    else
        error "SSH service failed to start"
        error "Check logs: journalctl -u ssh"
        exit 1
    fi
}

# Display SSH connection information
display_connection_info() {
    print_section "SSH Connection Information"

    echo
    echo -e "${GREEN}🔐 SSH Setup Complete!${NC}"
    echo
    echo -e "${BLUE}Connection Details:${NC}"
    echo -e "  ${YELLOW}Port:${NC} $DEFAULT_SSH_PORT"
    echo -e "  ${YELLOW}User:${NC} pi"
    echo -e "  ${YELLOW}Authentication:${NC} Key-based only"
    echo -e "  ${YELLOW}Private Key:${NC} /home/pi/.ssh/id_$SSH_KEY_TYPE"
    echo
    echo -e "${BLUE}Connection Commands:${NC}"
    echo -e "  ${PURPLE}Local:${NC} ssh -p $DEFAULT_SSH_PORT pi@localhost"
    echo -e "  ${PURPLE}Remote:${NC} ssh -p $DEFAULT_SSH_PORT pi@<your-pi-ip>"
    echo
    echo -e "${YELLOW}⚠️  Important Security Notes:${NC}"
    echo -e "  • Password authentication is disabled"
    echo -e "  • Root login is disabled"
    echo -e "  • SSH is running on port $DEFAULT_SSH_PORT (not 22)"
    echo -e "  • Copy your private key to client machines for access"
    echo -e "  • Update your router/firewall to allow port $DEFAULT_SSH_PORT"
    echo

    if [[ "$DRY_RUN" == "false" ]]; then
        echo -e "${BLUE}Private Key (copy to your client):${NC}"
        echo -e "${PURPLE}========================================${NC}"
        if [[ -f "/home/pi/.ssh/id_$SSH_KEY_TYPE" ]]; then
            cat "/home/pi/.ssh/id_$SSH_KEY_TYPE"
        fi
        echo -e "${PURPLE}========================================${NC}"
        echo
    fi

    success "SSH hardening setup completed successfully!"
}

# Main execution
main() {
    print_header

    log "INFO" "Starting Pi Gateway SSH setup"

    # Initialize dry-run environment
    init_dry_run_environment

    # Pre-setup checks
    check_sudo

    # Setup process
    backup_ssh_config
    generate_host_keys
    generate_user_keys
    configure_sshd
    create_ssh_banner
    configure_ssh_client
    test_ssh_config
    restart_ssh_service

    # Final information
    display_connection_info

    log "INFO" "Pi Gateway SSH setup completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi