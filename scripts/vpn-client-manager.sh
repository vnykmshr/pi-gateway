#!/bin/bash
#
# Pi Gateway VPN Client Manager
# Simple WireGuard client management utility
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
readonly WG_CONFIG_DIR="/etc/wireguard"
readonly CLIENT_CONFIG_DIR="$WG_CONFIG_DIR/clients"
readonly SERVER_CONFIG="$WG_CONFIG_DIR/wg0.conf"
readonly VPN_NETWORK="10.13.13.0/24"

# Logging functions
success() { echo -e "  ${GREEN}✓${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

# Check requirements
check_requirements() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi

    if ! command -v wg >/dev/null 2>&1; then
        error "WireGuard not installed"
        exit 1
    fi

    if [[ ! -f "$SERVER_CONFIG" ]]; then
        error "WireGuard server configuration not found: $SERVER_CONFIG"
        exit 1
    fi

    mkdir -p "$CLIENT_CONFIG_DIR"
}

# Get next available IP
get_next_client_ip() {
    local network_base="10.13.13"
    local used_ips

    # Get IPs from server config and existing client configs
    used_ips=$(grep -h "Address\|AllowedIPs" "$SERVER_CONFIG" "$CLIENT_CONFIG_DIR"/*.conf 2>/dev/null | \
               grep -oE "$network_base\.[0-9]+" | sort -n -t. -k4 | uniq || true)

    # Find first available IP (starting from .2)
    for i in {2..254}; do
        local test_ip="$network_base.$i"
        if ! echo "$used_ips" | grep -q "^$test_ip$"; then
            echo "$test_ip"
            return
        fi
    done

    error "No available IP addresses in VPN network"
    exit 1
}

# Generate key pair
generate_keypair() {
    local private_key public_key
    private_key=$(wg genkey)
    public_key=$(echo "$private_key" | wg pubkey)
    echo "$private_key $public_key"
}

# Add VPN client
add_client() {
    local client_name="$1"
    local client_config="$CLIENT_CONFIG_DIR/$client_name.conf"

    if [[ -f "$client_config" ]]; then
        error "Client '$client_name' already exists"
        return 1
    fi

    info "Generating client configuration for '$client_name'..."

    # Generate client keys
    local keys client_private_key client_public_key
    keys=$(generate_keypair)
    client_private_key=$(echo "$keys" | cut -d' ' -f1)
    client_public_key=$(echo "$keys" | cut -d' ' -f2)

    # Get server public key
    local server_public_key
    server_public_key=$(grep "PrivateKey" "$SERVER_CONFIG" | cut -d' ' -f3 | wg pubkey)

    # Get next available IP
    local client_ip
    client_ip=$(get_next_client_ip)

    # Get server endpoint
    local server_endpoint
    if command -v curl >/dev/null 2>&1; then
        local external_ip
        external_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
        server_endpoint="$external_ip:51820"
    else
        server_endpoint="YOUR_SERVER_IP:51820"
    fi

    # Create client configuration
    cat > "$client_config" << EOF
[Interface]
PrivateKey = $client_private_key
Address = $client_ip/32
DNS = 1.1.1.1

[Peer]
PublicKey = $server_public_key
Endpoint = $server_endpoint
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21
EOF

    # Add client to server configuration
    cat >> "$SERVER_CONFIG" << EOF

# Client: $client_name
[Peer]
PublicKey = $client_public_key
AllowedIPs = $client_ip/32
EOF

    # Restart WireGuard service
    if systemctl is-active --quiet wg-quick@wg0; then
        info "Restarting WireGuard service..."
        systemctl restart wg-quick@wg0
    fi

    success "Client '$client_name' added successfully"
    info "Client IP: $client_ip"
    info "Configuration saved to: $client_config"

    # Generate QR code if qrencode is available
    if command -v qrencode >/dev/null 2>&1; then
        echo
        info "QR Code for mobile devices:"
        qrencode -t ansiutf8 < "$client_config"
    else
        warning "Install 'qrencode' to generate QR codes for mobile devices"
        info "Run: sudo apt install qrencode"
    fi
}

# Remove VPN client
remove_client() {
    local client_name="$1"
    local client_config="$CLIENT_CONFIG_DIR/$client_name.conf"

    if [[ ! -f "$client_config" ]]; then
        error "Client '$client_name' not found"
        return 1
    fi

    # Get client public key
    local client_public_key
    client_public_key=$(grep "PrivateKey" "$client_config" | cut -d' ' -f3 | wg pubkey)

    # Remove client from server configuration
    local temp_config
    temp_config=$(mktemp)
    awk -v client="$client_name" -v pubkey="$client_public_key" '
        /^# Client: / { if ($3 == client) skip=1; next }
        /^\[Peer\]/ && skip { skip=2; next }
        /^PublicKey = / && skip==2 { if ($3 == pubkey) skip=3; else skip=0 }
        /^AllowedIPs = / && skip==3 { skip=0; next }
        /^$/ && skip { skip=0; next }
        !skip { print }
    ' "$SERVER_CONFIG" > "$temp_config"

    mv "$temp_config" "$SERVER_CONFIG"

    # Archive client configuration
    local archive_dir="$CLIENT_CONFIG_DIR/archived"
    mkdir -p "$archive_dir"
    mv "$client_config" "$archive_dir/$client_name-$(date +%Y%m%d-%H%M%S).conf"

    # Restart WireGuard service
    if systemctl is-active --quiet wg-quick@wg0; then
        info "Restarting WireGuard service..."
        systemctl restart wg-quick@wg0
    fi

    success "Client '$client_name' removed successfully"
    info "Configuration archived to: $archive_dir/"
}

# List VPN clients
list_clients() {
    echo -e "${CYAN}📋 VPN Client Status${NC}"
    echo

    if [[ ! -d "$CLIENT_CONFIG_DIR" ]] || [[ -z "$(ls -A "$CLIENT_CONFIG_DIR"/*.conf 2>/dev/null || true)" ]]; then
        warning "No VPN clients configured"
        return
    fi

    echo -e "${BLUE}Configured Clients:${NC}"
    for config in "$CLIENT_CONFIG_DIR"/*.conf; do
        if [[ -f "$config" ]]; then
            local client_name
            client_name=$(basename "$config" .conf)
            local client_ip
            client_ip=$(grep "Address" "$config" | cut -d' ' -f3)
            success "$client_name (IP: $client_ip)"
        fi
    done
    echo

    # Show active connections if WireGuard is running
    if command -v wg >/dev/null 2>&1 && wg show wg0 >/dev/null 2>&1; then
        echo -e "${BLUE}Active Connections:${NC}"
        local peer_count
        peer_count=$(wg show wg0 peers | wc -l)
        info "Connected peers: $peer_count"

        if [[ $peer_count -gt 0 ]]; then
            echo
            wg show wg0
        fi
    else
        warning "WireGuard interface not active"
    fi
}

# Show client configuration
show_client() {
    local client_name="$1"
    local client_config="$CLIENT_CONFIG_DIR/$client_name.conf"

    if [[ ! -f "$client_config" ]]; then
        error "Client '$client_name' not found"
        return 1
    fi

    echo -e "${CYAN}📄 Client Configuration: $client_name${NC}"
    echo
    cat "$client_config"
    echo

    # Generate QR code if available
    if command -v qrencode >/dev/null 2>&1; then
        echo -e "${BLUE}QR Code:${NC}"
        qrencode -t ansiutf8 < "$client_config"
    fi
}

# Show help
show_help() {
    echo "Pi Gateway VPN Client Manager"
    echo
    echo "Usage: $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "  add <name>       Add new VPN client"
    echo "  remove <name>    Remove VPN client"
    echo "  list             List all VPN clients"
    echo "  show <name>      Show client configuration and QR code"
    echo "  help             Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0") add laptop"
    echo "  $(basename "$0") remove old-phone"
    echo "  $(basename "$0") list"
    echo "  $(basename "$0") show mobile"
    echo
}

# Main execution
main() {
    local command="${1:-}"

    case $command in
        add)
            check_requirements
            local client_name="${2:-}"
            if [[ -z "$client_name" ]]; then
                error "Client name required"
                echo "Usage: $(basename "$0") add <client-name>"
                exit 1
            fi
            add_client "$client_name"
            ;;
        remove|rm)
            check_requirements
            local client_name="${2:-}"
            if [[ -z "$client_name" ]]; then
                error "Client name required"
                echo "Usage: $(basename "$0") remove <client-name>"
                exit 1
            fi
            remove_client "$client_name"
            ;;
        list|ls)
            list_clients
            ;;
        show)
            local client_name="${2:-}"
            if [[ -z "$client_name" ]]; then
                error "Client name required"
                echo "Usage: $(basename "$0") show <client-name>"
                exit 1
            fi
            show_client "$client_name"
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
