#!/bin/bash
#
# Pi Gateway Network Performance Optimizer
# Advanced network tuning, traffic shaping, and performance optimization
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="/etc/pi-gateway/network-optimizer.conf"
readonly LOG_FILE="/var/log/pi-gateway/network-optimizer.log"
readonly STATE_FILE="/var/lib/pi-gateway/network-state.json"

# Default optimization settings
readonly DEFAULT_ENABLE_TCP_OPTIMIZATION=true
readonly DEFAULT_ENABLE_BUFFER_TUNING=true
readonly DEFAULT_ENABLE_CONGESTION_CONTROL=true
readonly DEFAULT_ENABLE_TRAFFIC_SHAPING=false
readonly DEFAULT_ENABLE_QOS=false
readonly DEFAULT_VPN_OPTIMIZATION=true

# Network interface detection
PRIMARY_INTERFACE=""
WIFI_INTERFACE=""
VPN_INTERFACE="wg0"

# Logging functions
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level: $*" | tee -a "$LOG_FILE"
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

header() {
    echo
    echo -e "${CYAN}$1${NC}"
    echo
}

# Initialize network optimizer
initialize_optimizer() {
    # Create directories
    for dir in "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            sudo chown pi:pi "$dir" 2>/dev/null || true
        fi
    done

    # Detect network interfaces
    detect_network_interfaces

    # Create configuration if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_default_config
    fi

    # Load configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Detect network interfaces
detect_network_interfaces() {
    info "Detecting network interfaces..."

    # Find primary interface (usually eth0 or the interface with default route)
    PRIMARY_INTERFACE=$(ip route | grep default | head -n1 | awk '{print $5}' 2>/dev/null || echo "")

    # Find WiFi interface
    WIFI_INTERFACE=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -n1 || echo "")

    if [[ -n "$PRIMARY_INTERFACE" ]]; then
        success "Primary interface detected: $PRIMARY_INTERFACE"
    else
        warning "Could not detect primary network interface"
        PRIMARY_INTERFACE="eth0"  # Fallback
    fi

    if [[ -n "$WIFI_INTERFACE" ]]; then
        info "WiFi interface detected: $WIFI_INTERFACE"
    fi

    # Check VPN interface
    if ip link show "$VPN_INTERFACE" >/dev/null 2>&1; then
        info "VPN interface detected: $VPN_INTERFACE"
    fi
}

# Create default configuration
create_default_config() {
    info "Creating default network optimizer configuration"

    sudo mkdir -p "$(dirname "$CONFIG_FILE")"

    sudo tee "$CONFIG_FILE" > /dev/null << EOF
# Pi Gateway Network Optimizer Configuration

# TCP Optimization
ENABLE_TCP_OPTIMIZATION=$DEFAULT_ENABLE_TCP_OPTIMIZATION
TCP_CONGESTION_CONTROL="bbr"  # bbr, cubic, reno
TCP_WINDOW_SCALING=true
TCP_FAST_OPEN=true
TCP_TIMESTAMPS=true

# Buffer Tuning
ENABLE_BUFFER_TUNING=$DEFAULT_ENABLE_BUFFER_TUNING
NET_CORE_RMEM_MAX=134217728    # 128MB
NET_CORE_WMEM_MAX=134217728    # 128MB
NET_CORE_NETDEV_MAX_BACKLOG=5000
NET_IPV4_TCP_RMEM="4096 65536 134217728"
NET_IPV4_TCP_WMEM="4096 65536 134217728"

# VPN Optimization
ENABLE_VPN_OPTIMIZATION=$DEFAULT_VPN_OPTIMIZATION
WIREGUARD_MTU=1420
WIREGUARD_FWMARK=51820

# Traffic Shaping
ENABLE_TRAFFIC_SHAPING=$DEFAULT_ENABLE_TRAFFIC_SHAPING
DOWNLOAD_BANDWIDTH_MBPS=100
UPLOAD_BANDWIDTH_MBPS=20
PRIORITY_PORTS="22,53,80,443"

# Quality of Service (QoS)
ENABLE_QOS=$DEFAULT_ENABLE_QOS
QOS_HIGH_PRIORITY="ssh,dns,http,https"
QOS_LOW_PRIORITY="torrents,p2p"

# Interface Optimization
ETHERNET_OFFLOAD=true
WIFI_POWER_SAVE=false
INTERRUPT_BALANCING=true

# Performance Monitoring
ENABLE_BANDWIDTH_MONITORING=true
ENABLE_LATENCY_MONITORING=true
ENABLE_CONNECTION_TRACKING=true

# Advanced Settings
IPV6_OPTIMIZATION=true
REVERSE_PATH_FILTERING=1
SYN_COOKIES=true
TCP_SYN_RETRIES=3
TCP_RETRIES2=5
EOF

    sudo chown root:pi "$CONFIG_FILE"
    sudo chmod 640 "$CONFIG_FILE"

    success "Default configuration created at $CONFIG_FILE"
}

# Apply TCP optimizations
optimize_tcp() {
    header "🚀 TCP Optimization"

    if [[ "${ENABLE_TCP_OPTIMIZATION:-true}" != "true" ]]; then
        info "TCP optimization disabled in configuration"
        return 0
    fi

    local sysctl_changes=()

    # TCP Congestion Control
    local congestion_control="${TCP_CONGESTION_CONTROL:-bbr}"
    if grep -q "$congestion_control" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        sysctl_changes+=("net.ipv4.tcp_congestion_control=$congestion_control")
        info "Setting TCP congestion control to $congestion_control"
    else
        warning "Congestion control $congestion_control not available, using default"
    fi

    # TCP Window Scaling
    if [[ "${TCP_WINDOW_SCALING:-true}" == "true" ]]; then
        sysctl_changes+=("net.ipv4.tcp_window_scaling=1")
    fi

    # TCP Fast Open
    if [[ "${TCP_FAST_OPEN:-true}" == "true" ]]; then
        sysctl_changes+=("net.ipv4.tcp_fastopen=3")
    fi

    # TCP Timestamps
    if [[ "${TCP_TIMESTAMPS:-true}" == "true" ]]; then
        sysctl_changes+=("net.ipv4.tcp_timestamps=1")
    fi

    # Additional TCP optimizations
    sysctl_changes+=(
        "net.ipv4.tcp_slow_start_after_idle=0"
        "net.ipv4.tcp_mtu_probing=1"
        "net.ipv4.tcp_base_mss=1024"
        "net.ipv4.tcp_syn_retries=${TCP_SYN_RETRIES:-3}"
        "net.ipv4.tcp_retries2=${TCP_RETRIES2:-5}"
    )

    # SYN Cookies for DDoS protection
    if [[ "${SYN_COOKIES:-true}" == "true" ]]; then
        sysctl_changes+=("net.ipv4.tcp_syncookies=1")
    fi

    # Apply changes
    apply_sysctl_changes "${sysctl_changes[@]}"

    success "TCP optimization applied"
}

# Apply buffer tuning
optimize_buffers() {
    header "📊 Buffer Tuning"

    if [[ "${ENABLE_BUFFER_TUNING:-true}" != "true" ]]; then
        info "Buffer tuning disabled in configuration"
        return 0
    fi

    local sysctl_changes=()

    # Core network buffers
    sysctl_changes+=(
        "net.core.rmem_max=${NET_CORE_RMEM_MAX:-134217728}"
        "net.core.wmem_max=${NET_CORE_WMEM_MAX:-134217728}"
        "net.core.rmem_default=262144"
        "net.core.wmem_default=262144"
        "net.core.netdev_max_backlog=${NET_CORE_NETDEV_MAX_BACKLOG:-5000}"
        "net.core.netdev_budget=600"
    )

    # TCP socket buffers
    if [[ -n "${NET_IPV4_TCP_RMEM:-}" ]]; then
        sysctl_changes+=("net.ipv4.tcp_rmem=${NET_IPV4_TCP_RMEM}")
    fi

    if [[ -n "${NET_IPV4_TCP_WMEM:-}" ]]; then
        sysctl_changes+=("net.ipv4.tcp_wmem=${NET_IPV4_TCP_WMEM}")
    fi

    # UDP buffers
    sysctl_changes+=(
        "net.ipv4.udp_rmem_min=8192"
        "net.ipv4.udp_wmem_min=8192"
    )

    # Apply changes
    apply_sysctl_changes "${sysctl_changes[@]}"

    success "Buffer tuning applied"
}

# Optimize VPN performance
optimize_vpn() {
    header "🔒 VPN Optimization"

    if [[ "${ENABLE_VPN_OPTIMIZATION:-true}" != "true" ]]; then
        info "VPN optimization disabled in configuration"
        return 0
    fi

    # WireGuard MTU optimization
    local wireguard_mtu="${WIREGUARD_MTU:-1420}"
    if ip link show "$VPN_INTERFACE" >/dev/null 2>&1; then
        if sudo ip link set dev "$VPN_INTERFACE" mtu "$wireguard_mtu" 2>/dev/null; then
            success "WireGuard MTU set to $wireguard_mtu"
        else
            warning "Could not set WireGuard MTU"
        fi
    fi

    # VPN-specific optimizations
    local sysctl_changes=(
        "net.ipv4.ip_forward=1"
        "net.ipv6.conf.all.forwarding=1"
        "net.ipv4.conf.all.proxy_arp=1"
    )

    # Firewall mark for WireGuard
    local fwmark="${WIREGUARD_FWMARK:-51820}"
    if command -v wg >/dev/null 2>&1; then
        info "Optimizing WireGuard firewall marks"
        # This would be handled in WireGuard configuration
    fi

    apply_sysctl_changes "${sysctl_changes[@]}"

    success "VPN optimization applied"
}

# Apply traffic shaping
apply_traffic_shaping() {
    header "🚦 Traffic Shaping"

    if [[ "${ENABLE_TRAFFIC_SHAPING:-false}" != "true" ]]; then
        info "Traffic shaping disabled in configuration"
        return 0
    fi

    if ! command -v tc >/dev/null 2>&1; then
        warning "Traffic control (tc) not available"
        return 1
    fi

    local interface="$PRIMARY_INTERFACE"
    local download_bw="${DOWNLOAD_BANDWIDTH_MBPS:-100}"
    local upload_bw="${UPLOAD_BANDWIDTH_MBPS:-20}"

    # Clear existing rules
    sudo tc qdisc del dev "$interface" root 2>/dev/null || true

    # Create root qdisc with HTB (Hierarchical Token Bucket)
    sudo tc qdisc add dev "$interface" root handle 1: htb default 30

    # Create main class
    sudo tc class add dev "$interface" parent 1: classid 1:1 htb rate "${upload_bw}mbit"

    # Create priority classes
    sudo tc class add dev "$interface" parent 1:1 classid 1:10 htb rate "$((upload_bw * 70 / 100))mbit" ceil "${upload_bw}mbit" prio 1
    sudo tc class add dev "$interface" parent 1:1 classid 1:20 htb rate "$((upload_bw * 20 / 100))mbit" ceil "${upload_bw}mbit" prio 2
    sudo tc class add dev "$interface" parent 1:1 classid 1:30 htb rate "$((upload_bw * 10 / 100))mbit" ceil "${upload_bw}mbit" prio 3

    # Add fairness queues
    sudo tc qdisc add dev "$interface" parent 1:10 handle 10: sfq perturb 10
    sudo tc qdisc add dev "$interface" parent 1:20 handle 20: sfq perturb 10
    sudo tc qdisc add dev "$interface" parent 1:30 handle 30: sfq perturb 10

    # Priority port filters
    local priority_ports="${PRIORITY_PORTS:-22,53,80,443}"
    IFS=',' read -ra PORTS <<< "$priority_ports"
    for port in "${PORTS[@]}"; do
        sudo tc filter add dev "$interface" parent 1:0 protocol ip prio 1 u32 match ip dport "$port" 0xffff flowid 1:10
        sudo tc filter add dev "$interface" parent 1:0 protocol ip prio 1 u32 match ip sport "$port" 0xffff flowid 1:10
    done

    success "Traffic shaping applied (Upload: ${upload_bw}Mbps)"
}

# Apply Quality of Service
apply_qos() {
    header "⭐ Quality of Service"

    if [[ "${ENABLE_QOS:-false}" != "true" ]]; then
        info "QoS disabled in configuration"
        return 0
    fi

    # This is a simplified QoS implementation
    # In production, you might want to use more sophisticated tools

    local sysctl_changes=(
        "net.core.default_qdisc=fq_codel"
        "net.ipv4.tcp_ecn=1"
    )

    apply_sysctl_changes "${sysctl_changes[@]}"

    success "QoS optimization applied"
}

# Optimize network interfaces
optimize_interfaces() {
    header "🔧 Interface Optimization"

    # Ethernet optimizations
    if [[ "${ETHERNET_OFFLOAD:-true}" == "true" ]] && [[ -n "$PRIMARY_INTERFACE" ]]; then
        info "Optimizing Ethernet interface: $PRIMARY_INTERFACE"

        # Enable hardware offloading if supported
        local offload_features=("rx" "tx" "sg" "tso" "gso" "gro")

        for feature in "${offload_features[@]}"; do
            if sudo ethtool -K "$PRIMARY_INTERFACE" "$feature" on 2>/dev/null; then
                info "Enabled $feature offload on $PRIMARY_INTERFACE"
            fi
        done

        # Optimize ring buffers if possible
        if sudo ethtool -G "$PRIMARY_INTERFACE" rx 512 tx 512 2>/dev/null; then
            info "Optimized ring buffers on $PRIMARY_INTERFACE"
        fi
    fi

    # WiFi optimizations
    if [[ "${WIFI_POWER_SAVE:-false}" == "false" ]] && [[ -n "$WIFI_INTERFACE" ]]; then
        info "Disabling WiFi power save on $WIFI_INTERFACE"

        if sudo iw dev "$WIFI_INTERFACE" set power_save off 2>/dev/null; then
            success "WiFi power save disabled"
        else
            warning "Could not disable WiFi power save"
        fi
    fi

    # Interrupt balancing
    if [[ "${INTERRUPT_BALANCING:-true}" == "true" ]]; then
        if command -v irqbalance >/dev/null 2>&1; then
            if sudo systemctl is-active --quiet irqbalance; then
                info "IRQ balancing is already active"
            else
                sudo systemctl enable irqbalance 2>/dev/null || true
                sudo systemctl start irqbalance 2>/dev/null || true
                success "IRQ balancing enabled"
            fi
        fi
    fi

    success "Interface optimization completed"
}

# Apply IPv6 optimizations
optimize_ipv6() {
    if [[ "${IPV6_OPTIMIZATION:-true}" != "true" ]]; then
        return 0
    fi

    info "Applying IPv6 optimizations"

    local sysctl_changes=(
        "net.ipv6.conf.all.accept_ra=1"
        "net.ipv6.conf.default.accept_ra=1"
        "net.ipv6.conf.all.autoconf=1"
        "net.ipv6.conf.default.autoconf=1"
    )

    apply_sysctl_changes "${sysctl_changes[@]}"
}

# Apply security-related network optimizations
optimize_security() {
    info "Applying network security optimizations"

    local sysctl_changes=(
        "net.ipv4.conf.all.rp_filter=${REVERSE_PATH_FILTERING:-1}"
        "net.ipv4.conf.default.rp_filter=${REVERSE_PATH_FILTERING:-1}"
        "net.ipv4.conf.all.accept_source_route=0"
        "net.ipv4.conf.default.accept_source_route=0"
        "net.ipv4.conf.all.accept_redirects=0"
        "net.ipv4.conf.default.accept_redirects=0"
        "net.ipv4.conf.all.secure_redirects=0"
        "net.ipv4.conf.default.secure_redirects=0"
        "net.ipv4.conf.all.send_redirects=0"
        "net.ipv4.conf.default.send_redirects=0"
        "net.ipv4.icmp_echo_ignore_broadcasts=1"
        "net.ipv4.icmp_ignore_bogus_error_responses=1"
    )

    apply_sysctl_changes "${sysctl_changes[@]}"
}

# Apply sysctl changes
apply_sysctl_changes() {
    local changes=("$@")

    for change in "${changes[@]}"; do
        if echo "$change" | sudo tee -a /etc/sysctl.d/99-pi-gateway-network.conf >/dev/null; then
            # Also apply immediately
            local key value
            key=$(echo "$change" | cut -d'=' -f1)
            value=$(echo "$change" | cut -d'=' -f2-)

            if echo "$value" | sudo tee "/proc/sys/$(echo "$key" | tr '.' '/')" >/dev/null 2>&1; then
                info "Applied: $change"
            else
                warning "Could not apply immediately: $change"
            fi
        fi
    done
}

# Monitor network performance
monitor_performance() {
    header "📊 Network Performance Monitoring"

    if [[ "${ENABLE_BANDWIDTH_MONITORING:-true}" == "true" ]]; then
        info "Monitoring bandwidth usage..."

        # Simple bandwidth monitoring
        local interface="$PRIMARY_INTERFACE"
        if [[ -n "$interface" ]]; then
            local rx_bytes tx_bytes
            rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
            tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")

            local rx_mb tx_mb
            rx_mb=$((rx_bytes / 1024 / 1024))
            tx_mb=$((tx_bytes / 1024 / 1024))

            info "Interface $interface: RX ${rx_mb}MB, TX ${tx_mb}MB"
        fi
    fi

    if [[ "${ENABLE_LATENCY_MONITORING:-true}" == "true" ]]; then
        info "Testing network latency..."

        local ping_result
        if ping_result=$(ping -c 3 -W 5 8.8.8.8 2>/dev/null | grep "avg"); then
            local avg_latency
            avg_latency=$(echo "$ping_result" | awk -F'/' '{print $5}')
            info "Average latency to 8.8.8.8: ${avg_latency}ms"
        else
            warning "Could not measure network latency"
        fi
    fi

    if [[ "${ENABLE_CONNECTION_TRACKING:-true}" == "true" ]]; then
        local active_connections
        active_connections=$(ss -tupn | grep ESTAB | wc -l 2>/dev/null || echo "0")
        info "Active connections: $active_connections"
    fi
}

# Save current network state
save_network_state() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local state_json

    # Collect network information
    local interface_info=$(ip -j addr show 2>/dev/null || echo "[]")
    local route_info=$(ip -j route show 2>/dev/null || echo "[]")

    state_json=$(cat << EOF
{
    "timestamp": "$timestamp",
    "primary_interface": "$PRIMARY_INTERFACE",
    "wifi_interface": "$WIFI_INTERFACE",
    "vpn_interface": "$VPN_INTERFACE",
    "optimizations_applied": {
        "tcp": ${ENABLE_TCP_OPTIMIZATION:-false},
        "buffers": ${ENABLE_BUFFER_TUNING:-false},
        "vpn": ${ENABLE_VPN_OPTIMIZATION:-false},
        "traffic_shaping": ${ENABLE_TRAFFIC_SHAPING:-false},
        "qos": ${ENABLE_QOS:-false}
    },
    "interfaces": $interface_info,
    "routes": $route_info
}
EOF
)

    echo "$state_json" > "$STATE_FILE"
}

# Run complete optimization
run_optimization() {
    header "🚀 Pi Gateway Network Optimization"

    initialize_optimizer

    info "Starting network optimization..."

    # Apply optimizations
    optimize_tcp
    optimize_buffers
    optimize_vpn
    optimize_interfaces
    optimize_ipv6
    optimize_security

    # Apply advanced features if enabled
    apply_traffic_shaping
    apply_qos

    # Monitor performance
    monitor_performance

    # Save state
    save_network_state

    # Make changes persistent
    info "Making changes persistent..."
    sudo sysctl -p /etc/sysctl.d/99-pi-gateway-network.conf >/dev/null 2>&1 || true

    success "Network optimization completed"

    header "📋 Optimization Summary"
    info "TCP optimization: ${ENABLE_TCP_OPTIMIZATION:-false}"
    info "Buffer tuning: ${ENABLE_BUFFER_TUNING:-false}"
    info "VPN optimization: ${ENABLE_VPN_OPTIMIZATION:-false}"
    info "Traffic shaping: ${ENABLE_TRAFFIC_SHAPING:-false}"
    info "QoS: ${ENABLE_QOS:-false}"
    info "Primary interface: $PRIMARY_INTERFACE"

    if [[ -n "$WIFI_INTERFACE" ]]; then
        info "WiFi interface: $WIFI_INTERFACE"
    fi

    info "Configuration saved to: $CONFIG_FILE"
    info "State saved to: $STATE_FILE"
    info "Logs available at: $LOG_FILE"
}

# Show current network status
show_status() {
    header "📊 Network Optimization Status"

    # Check if optimizations are active
    if [[ -f /etc/sysctl.d/99-pi-gateway-network.conf ]]; then
        success "Network optimizations: Active"
        info "Configuration file: /etc/sysctl.d/99-pi-gateway-network.conf"
    else
        warning "Network optimizations: Not applied"
    fi

    # Show current TCP congestion control
    local current_cc
    current_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "unknown")
    info "TCP congestion control: $current_cc"

    # Show buffer sizes
    local rmem_max wmem_max
    rmem_max=$(cat /proc/sys/net/core/rmem_max 2>/dev/null || echo "unknown")
    wmem_max=$(cat /proc/sys/net/core/wmem_max 2>/dev/null || echo "unknown")
    info "Max receive buffer: $rmem_max bytes"
    info "Max send buffer: $wmem_max bytes"

    # Show interface information
    detect_network_interfaces

    # Show traffic control status
    if command -v tc >/dev/null 2>&1 && [[ -n "$PRIMARY_INTERFACE" ]]; then
        if tc qdisc show dev "$PRIMARY_INTERFACE" | grep -q htb 2>/dev/null; then
            success "Traffic shaping: Active on $PRIMARY_INTERFACE"
        else
            info "Traffic shaping: Not active"
        fi
    fi
}

# Reset optimizations
reset_optimizations() {
    header "🔄 Resetting Network Optimizations"

    warning "This will remove all network optimizations"
    read -r -p "Are you sure you want to continue? [y/N]: " confirm

    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        info "Reset cancelled"
        return 0
    fi

    # Remove sysctl configuration
    if [[ -f /etc/sysctl.d/99-pi-gateway-network.conf ]]; then
        sudo rm -f /etc/sysctl.d/99-pi-gateway-network.conf
        success "Removed sysctl configuration"
    fi

    # Clear traffic control rules
    if command -v tc >/dev/null 2>&1 && [[ -n "$PRIMARY_INTERFACE" ]]; then
        sudo tc qdisc del dev "$PRIMARY_INTERFACE" root 2>/dev/null || true
        info "Cleared traffic control rules"
    fi

    # Reload default sysctl values
    sudo sysctl --system >/dev/null 2>&1 || true

    success "Network optimizations reset"
    warning "Reboot recommended to ensure all changes take effect"
}

# Show help
show_help() {
    echo "Pi Gateway Network Performance Optimizer"
    echo
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Options:"
    echo "  --optimize           Apply network optimizations"
    echo "  --status             Show current optimization status"
    echo "  --monitor            Monitor network performance"
    echo "  --reset              Reset all optimizations"
    echo "  --config             Show current configuration"
    echo "  --test               Test network performance"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0") --optimize     # Apply all optimizations"
    echo "  $(basename "$0") --status       # Check current status"
    echo "  $(basename "$0") --monitor      # Monitor performance"
    echo "  $(basename "$0") --test         # Run performance tests"
    echo
}

# Test network performance
test_performance() {
    header "🧪 Network Performance Test"

    # Basic connectivity test
    info "Testing basic connectivity..."
    if ping -c 3 -W 5 8.8.8.8 >/dev/null 2>&1; then
        success "Internet connectivity: OK"
    else
        error "Internet connectivity: Failed"
    fi

    # DNS resolution test
    info "Testing DNS resolution..."
    if nslookup google.com >/dev/null 2>&1; then
        success "DNS resolution: OK"
    else
        error "DNS resolution: Failed"
    fi

    # Speed test (if available)
    if command -v speedtest-cli >/dev/null 2>&1; then
        info "Running speed test..."
        speedtest-cli --simple 2>/dev/null || warning "Speed test failed"
    else
        info "Install speedtest-cli for bandwidth testing: pip3 install speedtest-cli"
    fi

    # Latency test to common destinations
    local destinations=("8.8.8.8" "1.1.1.1" "google.com")
    info "Testing latency to common destinations..."

    for dest in "${destinations[@]}"; do
        local result
        if result=$(ping -c 3 -W 5 "$dest" 2>/dev/null | grep "avg"); then
            local avg_latency
            avg_latency=$(echo "$result" | awk -F'/' '{print $5}')
            info "$dest: ${avg_latency}ms"
        else
            warning "$dest: Failed"
        fi
    done
}

# Show configuration
show_config() {
    header "⚙️ Current Configuration"

    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    else
        warning "Configuration file not found at $CONFIG_FILE"
        info "Run with --optimize to create default configuration"
    fi
}

# Main execution
main() {
    case "${1:-}" in
        --optimize)
            run_optimization
            ;;
        --status)
            show_status
            ;;
        --monitor)
            initialize_optimizer
            monitor_performance
            ;;
        --reset)
            reset_optimizations
            ;;
        --config)
            show_config
            ;;
        --test)
            test_performance
            ;;
        -h|--help)
            show_help
            ;;
        "")
            show_help
            echo
            echo "Choose an action or run with --help for more information"
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
