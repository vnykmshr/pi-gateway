#!/bin/bash
#
# Pi Gateway - WireGuard VPN Server Setup
# Secure VPN setup with client management and advanced routing
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
readonly LOG_FILE="/tmp/pi-gateway-vpn-setup.log"
readonly CONFIG_BACKUP_DIR="/etc/pi-gateway/backups/wireguard-$(date +%Y%m%d_%H%M%S)"
readonly WG_CONFIG_DIR="/etc/wireguard"
readonly WG_CONFIG_FILE="$WG_CONFIG_DIR/wg0.conf"
readonly WG_CLIENTS_DIR="$WG_CONFIG_DIR/clients"
readonly WG_KEYS_DIR="$WG_CONFIG_DIR/keys"
readonly DEFAULT_WG_PORT=51820
readonly VPN_NETWORK="10.13.13.0/24"
readonly VPN_SERVER_IP="10.13.13.1/24"
readonly DNS_SERVERS="1.1.1.1,1.0.0.1"

# WireGuard network interface
readonly WG_INTERFACE="wg0"

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
    echo -e "${BLUE}       Pi Gateway - WireGuard VPN Setup       ${NC}"
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
        echo -e "${PURPLE}   → All WireGuard configuration will be simulated${NC}"
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

# Check WireGuard installation
check_wireguard() {
    print_section "WireGuard Installation Check"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "WireGuard installation check skipped in dry-run mode"
        return 0
    fi

    if ! command -v wg >/dev/null 2>&1; then
        info "WireGuard not found, installing..."
        execute_command "apt update" "Update package repositories"
        execute_command "apt install -y wireguard wireguard-tools" "Install WireGuard"
        success "WireGuard installed successfully"
    else
        success "WireGuard is already installed"
    fi

    # Check kernel module
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! lsmod | grep -q wireguard; then
            execute_command "modprobe wireguard" "Load WireGuard kernel module"
            success "WireGuard kernel module loaded"
        else
            success "WireGuard kernel module already loaded"
        fi
    fi
}

# Backup existing WireGuard configuration
backup_wireguard_config() {
    print_section "Configuration Backup"

    execute_command "mkdir -p '$CONFIG_BACKUP_DIR'" "Create backup directory"

    if [[ -d "$WG_CONFIG_DIR" ]]; then
        execute_command "cp -r '$WG_CONFIG_DIR' '$CONFIG_BACKUP_DIR/'" "Backup WireGuard configuration"
        success "WireGuard configuration backed up"
    else
        info "No existing WireGuard configuration found"
    fi

    success "Configuration backup completed: $CONFIG_BACKUP_DIR"
}

# Create WireGuard directory structure
create_wireguard_directories() {
    print_section "Directory Structure Creation"

    local directories=(
        "$WG_CONFIG_DIR"
        "$WG_CLIENTS_DIR"
        "$WG_KEYS_DIR"
        "$WG_KEYS_DIR/server"
        "$WG_KEYS_DIR/clients"
    )

    for dir in "${directories[@]}"; do
        execute_command "mkdir -p '$dir'" "Create directory: $dir"
        execute_command "chmod 700 '$dir'" "Set directory permissions: $dir"
    done

    success "WireGuard directory structure created"
}

# Generate server keys
generate_server_keys() {
    print_section "Server Key Generation"

    local server_private_key="$WG_KEYS_DIR/server/private.key"
    local server_public_key="$WG_KEYS_DIR/server/public.key"

    if [[ ! -f "$server_private_key" ]] || [[ "$DRY_RUN" == "true" ]]; then
        execute_command "wg genkey > '$server_private_key'" "Generate server private key"
        execute_command "chmod 600 '$server_private_key'" "Set private key permissions"

        execute_command "wg pubkey < '$server_private_key' > '$server_public_key'" "Generate server public key"
        execute_command "chmod 644 '$server_public_key'" "Set public key permissions"

        success "Server keys generated successfully"
    else
        info "Server keys already exist"
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        info "Server public key: $(cat "$server_public_key" 2>/dev/null || echo "Generated")"
    else
        info "Server public key: [DRY-RUN] Generated public key"
    fi
}

# Detect primary network interface and IP
detect_network_config() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "eth0 192.168.1.100"
        return 0
    fi

    # Get default route interface
    local interface
    interface=$(ip route | grep default | head -n1 | awk '{print $5}' || echo "eth0")

    # Get IP address of the interface
    local ip_address
    ip_address=$(ip addr show "$interface" | grep 'inet ' | head -n1 | awk '{print $2}' | cut -d'/' -f1 || echo "192.168.1.100")

    echo "$interface $ip_address"
}

# Configure IP forwarding
configure_ip_forwarding() {
    print_section "IP Forwarding Configuration"

    # Enable IP forwarding in sysctl
    execute_command "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf" "Enable IPv4 forwarding"
    execute_command "echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf" "Enable IPv6 forwarding"

    # Apply immediately
    execute_command "sysctl -p" "Apply sysctl changes"

    success "IP forwarding configured"
}

# Create WireGuard server configuration
create_server_config() {
    print_section "Server Configuration"

    local server_private_key="$WG_KEYS_DIR/server/private.key"
    local network_info
    network_info=$(detect_network_config)
    local primary_interface
    primary_interface=$(echo "$network_info" | awk '{print $1}')
    local server_ip
    server_ip=$(echo "$network_info" | awk '{print $2}')

    # Read private key or use placeholder for dry-run
    local private_key_content
    if [[ "$DRY_RUN" == "true" ]]; then
        private_key_content="[DRY-RUN-PRIVATE-KEY]"
    else
        private_key_content=$(cat "$server_private_key" 2>/dev/null || echo "[KEY-NOT-FOUND]")
    fi

    execute_command "cat > '$WG_CONFIG_FILE' << 'EOF'
# Pi Gateway WireGuard Server Configuration
# Generated on $(date)
# Server: $server_ip:$DEFAULT_WG_PORT
# VPN Network: $VPN_NETWORK

[Interface]
# Server private key
PrivateKey = $private_key_content

# Server VPN IP address
Address = $VPN_SERVER_IP

# WireGuard listening port
ListenPort = $DEFAULT_WG_PORT

# DNS servers for VPN clients
DNS = $DNS_SERVERS

# Post-up script: Configure NAT and routing
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $primary_interface -j MASQUERADE
PostUp = ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -A FORWARD -o %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $primary_interface -j MASQUERADE

# Post-down script: Remove NAT and routing rules
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $primary_interface -j MASQUERADE
PostDown = ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -D FORWARD -o %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $primary_interface -j MASQUERADE

# Client configurations will be added below
# Use 'wg-quick up wg0' to start the VPN server
# Use 'wg-quick down wg0' to stop the VPN server

EOF" "Create WireGuard server configuration"

    execute_command "chmod 600 '$WG_CONFIG_FILE'" "Set server config permissions"
    success "WireGuard server configuration created"
}

# Configure WireGuard service
configure_wireguard_service() {
    print_section "WireGuard Service Configuration"

    # Enable WireGuard service
    execute_command "systemctl enable wg-quick@$WG_INTERFACE" "Enable WireGuard service"

    success "WireGuard service configured for automatic startup"
}

# Create client management scripts
create_client_management_scripts() {
    print_section "Client Management Scripts"

    # Create add-client script
    execute_command "cat > '/usr/local/bin/wg-add-client' << 'EOF'
#!/bin/bash
# WireGuard Client Addition Script
# Usage: wg-add-client <client-name> [client-ip]

set -euo pipefail

CLIENT_NAME=\"\${1:-}\"
CLIENT_IP=\"\${2:-}\"
WG_CONFIG_DIR=\"/etc/wireguard\"
WG_CONFIG_FILE=\"\$WG_CONFIG_DIR/wg0.conf\"
CLIENTS_DIR=\"\$WG_CONFIG_DIR/clients\"
KEYS_DIR=\"\$WG_CONFIG_DIR/keys/clients\"

if [[ -z \"\$CLIENT_NAME\" ]]; then
    echo \"Usage: wg-add-client <client-name> [client-ip]\"
    echo \"Example: wg-add-client laptop 10.13.13.2\"
    exit 1
fi

# Auto-assign IP if not provided
if [[ -z \"\$CLIENT_IP\" ]]; then
    # Find next available IP in 10.13.13.x range
    for i in {2..254}; do
        test_ip=\"10.13.13.\$i\"
        if ! grep -q \"\$test_ip\" \"\$WG_CONFIG_FILE\" 2>/dev/null; then
            CLIENT_IP=\"\$test_ip\"
            break
        fi
    done
fi

echo \"Adding WireGuard client: \$CLIENT_NAME (\$CLIENT_IP)\"

# Generate client keys
CLIENT_PRIVATE_KEY=\"\$KEYS_DIR/\$CLIENT_NAME.private\"
CLIENT_PUBLIC_KEY=\"\$KEYS_DIR/\$CLIENT_NAME.public\"

mkdir -p \"\$KEYS_DIR\"
wg genkey > \"\$CLIENT_PRIVATE_KEY\"
chmod 600 \"\$CLIENT_PRIVATE_KEY\"
wg pubkey < \"\$CLIENT_PRIVATE_KEY\" > \"\$CLIENT_PUBLIC_KEY\"
chmod 644 \"\$CLIENT_PUBLIC_KEY\"

# Get server public key
SERVER_PUBLIC_KEY=\$(cat \"\$WG_CONFIG_DIR/keys/server/public.key\")

# Get server endpoint (public IP or hostname)
SERVER_ENDPOINT=\$(curl -s https://ipinfo.io/ip || echo \"YOUR_SERVER_IP\")

# Create client configuration
CLIENT_CONFIG=\"\$CLIENTS_DIR/\$CLIENT_NAME.conf\"
mkdir -p \"\$CLIENTS_DIR\"

cat > \"\$CLIENT_CONFIG\" << CLIENTEOF
[Interface]
PrivateKey = \$(cat \"\$CLIENT_PRIVATE_KEY\")
Address = \$CLIENT_IP/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = \$SERVER_PUBLIC_KEY
Endpoint = \$SERVER_ENDPOINT:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CLIENTEOF

# Add client to server config
cat >> \"\$WG_CONFIG_FILE\" << SERVEREOF

# Client: \$CLIENT_NAME
[Peer]
PublicKey = \$(cat \"\$CLIENT_PUBLIC_KEY\")
AllowedIPs = \$CLIENT_IP/32
SERVEREOF

echo \"Client \$CLIENT_NAME added successfully!\"
echo \"Client config: \$CLIENT_CONFIG\"
echo \"Restart WireGuard: sudo systemctl restart wg-quick@wg0\"
EOF" "Create add-client script"

    execute_command "chmod +x '/usr/local/bin/wg-add-client'" "Make add-client script executable"

    # Create remove-client script
    execute_command "cat > '/usr/local/bin/wg-remove-client' << 'EOF'
#!/bin/bash
# WireGuard Client Removal Script
# Usage: wg-remove-client <client-name>

set -euo pipefail

CLIENT_NAME=\"\${1:-}\"
WG_CONFIG_DIR=\"/etc/wireguard\"
WG_CONFIG_FILE=\"\$WG_CONFIG_DIR/wg0.conf\"
CLIENTS_DIR=\"\$WG_CONFIG_DIR/clients\"
KEYS_DIR=\"\$WG_CONFIG_DIR/keys/clients\"

if [[ -z \"\$CLIENT_NAME\" ]]; then
    echo \"Usage: wg-remove-client <client-name>\"
    exit 1
fi

echo \"Removing WireGuard client: \$CLIENT_NAME\"

# Remove client keys
rm -f \"\$KEYS_DIR/\$CLIENT_NAME.private\"
rm -f \"\$KEYS_DIR/\$CLIENT_NAME.public\"

# Remove client config
rm -f \"\$CLIENTS_DIR/\$CLIENT_NAME.conf\"

# Remove from server config (requires manual editing or recreation)
echo \"Warning: Please manually remove client \$CLIENT_NAME from \$WG_CONFIG_FILE\"
echo \"Look for the section starting with '# Client: \$CLIENT_NAME'\"
echo \"Then restart WireGuard: sudo systemctl restart wg-quick@wg0\"
EOF" "Create remove-client script"

    execute_command "chmod +x '/usr/local/bin/wg-remove-client'" "Make remove-client script executable"

    # Create list-clients script
    execute_command "cat > '/usr/local/bin/wg-list-clients' << 'EOF'
#!/bin/bash
# WireGuard Client Listing Script
# Usage: wg-list-clients

WG_CONFIG_DIR=\"/etc/wireguard\"
CLIENTS_DIR=\"\$WG_CONFIG_DIR/clients\"

echo \"WireGuard VPN Clients:\"
echo \"=====================\"

if [[ -d \"\$CLIENTS_DIR\" ]]; then
    for config in \"\$CLIENTS_DIR\"/*.conf; do
        if [[ -f \"\$config\" ]]; then
            client_name=\$(basename \"\$config\" .conf)
            client_ip=\$(grep \"Address\" \"\$config\" | awk '{print \$3}' | cut -d'/' -f1)
            echo \"  \$client_name: \$client_ip\"
        fi
    done
else
    echo \"  No clients configured\"
fi

echo
echo \"Active WireGuard connections:\"
wg show 2>/dev/null || echo \"  WireGuard not running\"
EOF" "Create list-clients script"

    execute_command "chmod +x '/usr/local/bin/wg-list-clients'" "Make list-clients script executable"

    success "Client management scripts created"
}

# Start WireGuard service
start_wireguard_service() {
    print_section "WireGuard Service Startup"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "WireGuard service startup skipped in dry-run mode"
        return 0
    fi

    execute_command "systemctl start wg-quick@$WG_INTERFACE" "Start WireGuard service"
    success "WireGuard service started"

    # Check service status
    sleep 2
    if systemctl is-active wg-quick@$WG_INTERFACE >/dev/null 2>&1; then
        success "WireGuard service is running successfully"
    else
        error "WireGuard service failed to start"
        error "Check logs: journalctl -u wg-quick@$WG_INTERFACE"
        exit 1
    fi
}

# Display VPN connection information
display_connection_info() {
    print_section "WireGuard VPN Information"

    echo
    echo -e "${GREEN}🔐 WireGuard VPN Setup Complete!${NC}"
    echo
    echo -e "${BLUE}VPN Server Details:${NC}"
    echo -e "  ${YELLOW}Interface:${NC} $WG_INTERFACE"
    echo -e "  ${YELLOW}Port:${NC} $DEFAULT_WG_PORT"
    echo -e "  ${YELLOW}Network:${NC} $VPN_NETWORK"
    echo -e "  ${YELLOW}Server IP:${NC} $VPN_SERVER_IP"
    echo
    echo -e "${BLUE}Client Management:${NC}"
    echo -e "  ${PURPLE}Add client:${NC} wg-add-client <name> [ip]"
    echo -e "  ${PURPLE}Remove client:${NC} wg-remove-client <name>"
    echo -e "  ${PURPLE}List clients:${NC} wg-list-clients"
    echo
    echo -e "${BLUE}Service Management:${NC}"
    echo -e "  ${PURPLE}Start VPN:${NC} sudo systemctl start wg-quick@$WG_INTERFACE"
    echo -e "  ${PURPLE}Stop VPN:${NC} sudo systemctl stop wg-quick@$WG_INTERFACE"
    echo -e "  ${PURPLE}Status:${NC} sudo systemctl status wg-quick@$WG_INTERFACE"
    echo -e "  ${PURPLE}Show connections:${NC} sudo wg show"
    echo
    echo -e "${YELLOW}⚠️  Important Setup Notes:${NC}"
    echo -e "  • Configure your router to forward port $DEFAULT_WG_PORT to this Pi"
    echo -e "  • Update your Dynamic DNS if using external access"
    echo -e "  • Add clients using: wg-add-client laptop"
    echo -e "  • Client configs are stored in: $WG_CLIENTS_DIR"
    echo

    if [[ "$DRY_RUN" == "false" ]]; then
        local network_info
        network_info=$(detect_network_config)
        local server_ip
        server_ip=$(echo "$network_info" | awk '{print $2}')

        echo -e "${BLUE}Next Steps:${NC}"
        echo -e "  1. Add your first client: ${PURPLE}wg-add-client phone${NC}"
        echo -e "  2. Configure router port forwarding: ${PURPLE}$DEFAULT_WG_PORT → $server_ip${NC}"
        echo -e "  3. Test VPN connection from external network"
        echo
    fi

    success "WireGuard VPN setup completed successfully!"
}

# Main execution
main() {
    print_header

    log "INFO" "Starting Pi Gateway WireGuard VPN setup"

    # Initialize dry-run environment
    init_dry_run_environment

    # Pre-setup checks
    check_sudo
    check_wireguard

    # Setup process
    backup_wireguard_config
    create_wireguard_directories
    generate_server_keys
    configure_ip_forwarding
    create_server_config
    configure_wireguard_service
    create_client_management_scripts
    start_wireguard_service

    # Final information
    display_connection_info

    log "INFO" "Pi Gateway WireGuard VPN setup completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi