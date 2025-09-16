#!/bin/bash
#
# Pi Gateway - Service Status Checker
# Comprehensive health monitoring for all Pi Gateway services
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
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/pi-gateway-service-status.log"

# Service definitions
declare -A SERVICES=(
    ["ssh"]="SSH Server"
    ["ufw"]="Firewall (UFW)"
    ["fail2ban"]="Intrusion Detection"
    ["wg-quick@wg0"]="WireGuard VPN"
    ["ddclient"]="Dynamic DNS"
    ["vncserver@1"]="VNC Server"
    ["xrdp"]="RDP Server"
)

declare -A SERVICE_PORTS=(
    ["ssh"]="2222"
    ["wireguard"]="51820"
    ["vnc"]="5900"
    ["rdp"]="3389"
)

declare -A SERVICE_CONFIGS=(
    ["ssh"]="/etc/ssh/sshd_config"
    ["ufw"]="/etc/ufw/user.rules"
    ["fail2ban"]="/etc/fail2ban/jail.local"
    ["wireguard"]="/etc/wireguard/wg0.conf"
    ["ddclient"]="/etc/ddclient.conf"
    ["vnc"]="/home/pi/.vnc/xstartup"
    ["xrdp"]="/etc/xrdp/xrdp.ini"
)

# Status tracking
TOTAL_SERVICES=0
RUNNING_SERVICES=0
FAILED_SERVICES=0
WARNING_SERVICES=0

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

print_header() {
    clear
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    ${WHITE}Pi Gateway Service Status${NC}${BLUE}                   ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}📊 Comprehensive Health Check for Pi Gateway Services${NC}"
    echo
}

print_summary() {
    echo
    echo -e "${CYAN}📈 Service Status Summary:${NC}"
    echo -e "  ${GREEN}Running:${NC} $RUNNING_SERVICES/$TOTAL_SERVICES"
    echo -e "  ${RED}Failed:${NC} $FAILED_SERVICES/$TOTAL_SERVICES"
    echo -e "  ${YELLOW}Warnings:${NC} $WARNING_SERVICES/$TOTAL_SERVICES"
    echo

    if [[ $FAILED_SERVICES -eq 0 && $WARNING_SERVICES -eq 0 ]]; then
        echo -e "${GREEN}🎉 All services are running perfectly!${NC}"
    elif [[ $FAILED_SERVICES -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  All services running with some warnings${NC}"
    else
        echo -e "${RED}❌ Some services have failed - attention required${NC}"
    fi
}

# Service checking functions
check_systemd_service() {
    local service="$1"
    local description="$2"

    echo -e "${CYAN}🔍 Checking: $description${NC}"

    ((TOTAL_SERVICES++))

    if ! systemctl list-unit-files | grep -q "^$service"; then
        warning "$description: Service not installed"
        ((WARNING_SERVICES++))
        return 1
    fi

    local status
    status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")

    case $status in
        "active")
            success "$description: Active and running"
            ((RUNNING_SERVICES++))

            # Check if service is enabled
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                info "  └─ Service is enabled for automatic startup"
            else
                warning "  └─ Service is not enabled for automatic startup"
                ((WARNING_SERVICES++))
            fi

            # Show uptime
            local uptime
            uptime=$(systemctl show "$service" --property=ActiveEnterTimestamp --value 2>/dev/null | head -1)
            if [[ -n "$uptime" && "$uptime" != "n/a" ]]; then
                info "  └─ Running since: $uptime"
            fi
            return 0
            ;;
        "inactive")
            error "$description: Inactive (stopped)"
            ((FAILED_SERVICES++))
            return 1
            ;;
        "failed")
            error "$description: Failed to start"
            ((FAILED_SERVICES++))

            # Show failure reason
            local failure_reason
            failure_reason=$(systemctl show "$service" --property=Result --value 2>/dev/null)
            if [[ -n "$failure_reason" && "$failure_reason" != "success" ]]; then
                error "  └─ Failure reason: $failure_reason"
            fi
            return 1
            ;;
        *)
            warning "$description: Unknown status ($status)"
            ((WARNING_SERVICES++))
            return 1
            ;;
    esac
}

check_port_availability() {
    local port="$1"
    local service_name="$2"

    if command -v netstat >/dev/null 2>&1; then
        if netstat -ln | grep -q ":$port "; then
            success "Port $port ($service_name): Listening"
            return 0
        else
            warning "Port $port ($service_name): Not listening"
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -ln | grep -q ":$port "; then
            success "Port $port ($service_name): Listening"
            return 0
        else
            warning "Port $port ($service_name): Not listening"
            return 1
        fi
    else
        warning "Cannot check port $port: netstat/ss not available"
        return 1
    fi
}

check_configuration_files() {
    echo
    echo -e "${CYAN}📁 Configuration File Status:${NC}"

    for service in "${!SERVICE_CONFIGS[@]}"; do
        local config_file="${SERVICE_CONFIGS[$service]}"
        local service_name="$service"

        if [[ -f "$config_file" ]]; then
            success "$service_name config: Found ($config_file)"

            # Check file permissions
            local perms
            perms=$(stat -c "%a" "$config_file" 2>/dev/null || echo "unknown")
            if [[ "$perms" =~ ^[0-7]{3}$ ]]; then
                info "  └─ Permissions: $perms"

                # Check for secure permissions
                if [[ "$service_name" == "ssh" && "$perms" != "644" ]]; then
                    warning "  └─ SSH config should have 644 permissions"
                elif [[ "$service_name" == "wireguard" && "$perms" != "600" ]]; then
                    warning "  └─ WireGuard config should have 600 permissions"
                elif [[ "$service_name" == "ddclient" && "$perms" != "600" ]]; then
                    warning "  └─ DDClient config should have 600 permissions"
                fi
            fi

            # Check file size (empty configs are suspicious)
            local size
            size=$(stat -c "%s" "$config_file" 2>/dev/null || echo "0")
            if [[ "$size" -eq 0 ]]; then
                warning "  └─ Configuration file is empty"
            else
                info "  └─ File size: $size bytes"
            fi
        else
            warning "$service_name config: Not found ($config_file)"
        fi
    done
}

check_network_connectivity() {
    echo
    echo -e "${CYAN}🌐 Network Connectivity:${NC}"

    # Check internet connectivity
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        success "Internet connectivity: Available"
    else
        error "Internet connectivity: Failed"
    fi

    # Check DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        success "DNS resolution: Working"
    else
        warning "DNS resolution: Failed"
    fi

    # Check local network interface
    local primary_interface
    primary_interface=$(ip route | grep default | head -n1 | awk '{print $5}' 2>/dev/null || echo "unknown")

    if [[ "$primary_interface" != "unknown" ]]; then
        local ip_address
        ip_address=$(ip addr show "$primary_interface" | grep 'inet ' | head -n1 | awk '{print $2}' | cut -d'/' -f1 2>/dev/null || echo "unknown")

        if [[ "$ip_address" != "unknown" ]]; then
            success "Network interface: $primary_interface ($ip_address)"
        else
            warning "Network interface: $primary_interface (no IP)"
        fi
    else
        warning "Network interface: Cannot determine primary interface"
    fi
}

check_firewall_status() {
    echo
    echo -e "${CYAN}🔥 Firewall Status:${NC}"

    if command -v ufw >/dev/null 2>&1; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")

        case $ufw_status in
            "active")
                success "UFW Firewall: Active"

                # Show rule count
                local rule_count
                rule_count=$(ufw status numbered 2>/dev/null | grep -c "^\[" || echo "0")
                info "  └─ Active rules: $rule_count"
                ;;
            "inactive")
                warning "UFW Firewall: Inactive"
                ;;
            *)
                warning "UFW Firewall: Status unknown"
                ;;
        esac
    else
        warning "UFW Firewall: Not installed"
    fi

    # Check iptables rules
    if command -v iptables >/dev/null 2>&1; then
        local iptables_rules
        iptables_rules=$(iptables -L | wc -l 2>/dev/null || echo "0")
        info "Raw iptables rules: $iptables_rules lines"
    fi
}

check_vpn_status() {
    echo
    echo -e "${CYAN}🔒 VPN Status:${NC}"

    # Check WireGuard interface
    if command -v wg >/dev/null 2>&1; then
        if wg show wg0 >/dev/null 2>&1; then
            success "WireGuard Interface: Active"

            # Show peer count
            local peer_count
            peer_count=$(wg show wg0 peers 2>/dev/null | wc -l || echo "0")
            info "  └─ Connected peers: $peer_count"

            # Show interface details
            local listen_port
            listen_port=$(wg show wg0 listen-port 2>/dev/null || echo "unknown")
            if [[ "$listen_port" != "unknown" ]]; then
                info "  └─ Listen port: $listen_port"
            fi
        else
            warning "WireGuard Interface: Not active"
        fi
    else
        warning "WireGuard: Not installed"
    fi
}

check_system_resources() {
    echo
    echo -e "${CYAN}💻 System Resources:${NC}"

    # Check CPU usage
    if command -v top >/dev/null 2>&1; then
        local cpu_usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "unknown")
        if [[ "$cpu_usage" != "unknown" ]]; then
            success "CPU Usage: $cpu_usage%"
        fi
    fi

    # Check memory usage
    if command -v free >/dev/null 2>&1; then
        local memory_info
        memory_info=$(free -h | grep "Mem:" 2>/dev/null || echo "")
        if [[ -n "$memory_info" ]]; then
            local used
            local total
            used=$(echo "$memory_info" | awk '{print $3}')
            total=$(echo "$memory_info" | awk '{print $2}')
            success "Memory Usage: $used / $total"
        fi
    fi

    # Check disk usage
    local disk_usage
    disk_usage=$(df -h / | tail -1 | awk '{print $5}' 2>/dev/null || echo "unknown")
    if [[ "$disk_usage" != "unknown" ]]; then
        local usage_percent
        usage_percent=${disk_usage%\%}

        if [[ "$usage_percent" -lt 80 ]]; then
            success "Disk Usage: $disk_usage"
        elif [[ "$usage_percent" -lt 90 ]]; then
            warning "Disk Usage: $disk_usage (getting full)"
        else
            error "Disk Usage: $disk_usage (critically full)"
        fi
    fi

    # Check system uptime
    if command -v uptime >/dev/null 2>&1; then
        local uptime_info
        uptime_info=$(uptime | sed 's/.*up //' | sed 's/, [0-9]* user.*//' 2>/dev/null || echo "unknown")
        if [[ "$uptime_info" != "unknown" ]]; then
            success "System Uptime: $uptime_info"
        fi
    fi
}

check_log_files() {
    echo
    echo -e "${CYAN}📄 Log File Status:${NC}"

    local log_files=(
        "/var/log/auth.log:Authentication"
        "/var/log/syslog:System"
        "/var/log/ufw.log:Firewall"
        "/var/log/fail2ban.log:Fail2ban"
        "/var/log/ddclient.log:DDNS"
    )

    for log_entry in "${log_files[@]}"; do
        local log_file="${log_entry%%:*}"
        local log_name="${log_entry#*:}"

        if [[ -f "$log_file" ]]; then
            local size
            size=$(stat -c "%s" "$log_file" 2>/dev/null || echo "0")
            local size_human
            size_human=$(du -h "$log_file" 2>/dev/null | cut -f1 || echo "0")

            success "$log_name log: $size_human"

            # Check for recent activity
            local recent_lines
            recent_lines=$(tail -100 "$log_file" 2>/dev/null | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
            info "  └─ Today's entries: $recent_lines"
        else
            warning "$log_name log: Not found ($log_file)"
        fi
    done
}

# Main execution
main() {
    print_header

    log "INFO" "Starting Pi Gateway service status check"

    # Check core services
    echo -e "${CYAN}🔧 Core Services:${NC}"
    for service in "${!SERVICES[@]}"; do
        check_systemd_service "$service" "${SERVICES[$service]}"
        echo
    done

    # Check network ports
    echo -e "${CYAN}🔌 Network Ports:${NC}"
    for service in "${!SERVICE_PORTS[@]}"; do
        check_port_availability "${SERVICE_PORTS[$service]}" "$service"
    done

    # Additional checks
    check_configuration_files
    check_network_connectivity
    check_firewall_status
    check_vpn_status
    check_system_resources
    check_log_files

    # Display summary
    print_summary

    echo
    echo -e "${CYAN}🔗 Quick Commands:${NC}"
    echo -e "  ${YELLOW}Service logs:${NC} journalctl -u <service-name>"
    echo -e "  ${YELLOW}System logs:${NC} tail -f /var/log/syslog"
    echo -e "  ${YELLOW}Restart service:${NC} sudo systemctl restart <service-name>"
    echo -e "  ${YELLOW}Full status:${NC} $0"
    echo

    log "INFO" "Pi Gateway service status check completed"

    # Exit with appropriate code
    if [[ $FAILED_SERVICES -gt 0 ]]; then
        exit 1
    elif [[ $WARNING_SERVICES -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Show help
show_help() {
    echo "Pi Gateway Service Status Checker"
    echo
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -q, --quiet    Quiet mode (less output)"
    echo "  -j, --json     Output status in JSON format"
    echo
    echo "Exit codes:"
    echo "  0  All services running normally"
    echo "  1  One or more services failed"
    echo "  2  Services running with warnings"
    echo
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
