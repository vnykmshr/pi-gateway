#!/bin/bash
#
# Pi Gateway Advanced Monitoring System
# Comprehensive monitoring with alerts, metrics collection, and health analysis
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
readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_FILE="/etc/pi-gateway/monitoring.conf"
readonly METRICS_DIR="/var/lib/pi-gateway/metrics"
readonly ALERTS_DIR="/var/lib/pi-gateway/alerts"
readonly LOG_FILE="/var/log/pi-gateway/monitoring.log"

# Default thresholds
readonly DEFAULT_CPU_THRESHOLD=80
readonly DEFAULT_MEMORY_THRESHOLD=85
readonly DEFAULT_DISK_THRESHOLD=90
readonly DEFAULT_TEMP_THRESHOLD=75
readonly DEFAULT_LOAD_THRESHOLD=4.0

# Monitoring configuration
CPU_THRESHOLD=${CPU_THRESHOLD:-$DEFAULT_CPU_THRESHOLD}
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-$DEFAULT_MEMORY_THRESHOLD}
DISK_THRESHOLD=${DISK_THRESHOLD:-$DEFAULT_DISK_THRESHOLD}
TEMP_THRESHOLD=${TEMP_THRESHOLD:-$DEFAULT_TEMP_THRESHOLD}
LOAD_THRESHOLD=${LOAD_THRESHOLD:-$DEFAULT_LOAD_THRESHOLD}

# Alert configuration
ENABLE_EMAIL_ALERTS=${ENABLE_EMAIL_ALERTS:-false}
ENABLE_WEBHOOK_ALERTS=${ENABLE_WEBHOOK_ALERTS:-false}
ALERT_EMAIL=${ALERT_EMAIL:-""}
WEBHOOK_URL=${WEBHOOK_URL:-""}

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

critical() {
    echo -e "  ${RED}🚨${NC} $1"
    log "CRITICAL" "$1"
}

header() {
    echo
    echo -e "${CYAN}$1${NC}"
    echo
}

# Initialize monitoring system
initialize_monitoring() {
    header "🔧 Initializing Monitoring System"

    # Create directories
    for dir in "$METRICS_DIR" "$ALERTS_DIR" "$(dirname "$LOG_FILE")"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            sudo chown pi:pi "$dir" 2>/dev/null || true
        fi
    done

    # Create configuration if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_default_config
    fi

    # Load configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi

    success "Monitoring system initialized"
}

# Create default configuration
create_default_config() {
    info "Creating default monitoring configuration"

    sudo mkdir -p "$(dirname "$CONFIG_FILE")"

    sudo tee "$CONFIG_FILE" > /dev/null << EOF
# Pi Gateway Monitoring Configuration

# Threshold Settings
CPU_THRESHOLD=$DEFAULT_CPU_THRESHOLD
MEMORY_THRESHOLD=$DEFAULT_MEMORY_THRESHOLD
DISK_THRESHOLD=$DEFAULT_DISK_THRESHOLD
TEMP_THRESHOLD=$DEFAULT_TEMP_THRESHOLD
LOAD_THRESHOLD=$DEFAULT_LOAD_THRESHOLD

# Monitoring Intervals (seconds)
CHECK_INTERVAL=60
METRICS_RETENTION_DAYS=30

# Alert Settings
ENABLE_EMAIL_ALERTS=false
ENABLE_WEBHOOK_ALERTS=false
ENABLE_LOG_ALERTS=true

# Email Configuration
ALERT_EMAIL=""
SMTP_SERVER=""
SMTP_PORT=587
SMTP_USERNAME=""
SMTP_PASSWORD=""

# Webhook Configuration
WEBHOOK_URL=""
WEBHOOK_TIMEOUT=10

# Service Monitoring
MONITOR_SSH=true
MONITOR_VPN=true
MONITOR_FIREWALL=true
MONITOR_DNS=true

# Network Monitoring
MONITOR_BANDWIDTH=true
MONITOR_CONNECTIONS=true
MONITOR_LATENCY=true

# Security Monitoring
MONITOR_FAILED_LOGINS=true
MONITOR_INTRUSION_ATTEMPTS=true
MONITOR_PORT_SCANS=true
EOF

    sudo chown root:pi "$CONFIG_FILE"
    sudo chmod 640 "$CONFIG_FILE"

    success "Default configuration created at $CONFIG_FILE"
}

# Collect system metrics
collect_system_metrics() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local metrics_file="$METRICS_DIR/system-$(date '+%Y%m%d').json"

    # CPU Usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "0")

    # Memory Usage
    local memory_total memory_used memory_percent
    memory_info=$(free | grep '^Mem:')
    memory_total=$(echo "$memory_info" | awk '{print $2}')
    memory_used=$(echo "$memory_info" | awk '{print $3}')
    memory_percent=$(awk "BEGIN {printf \"%.1f\", $memory_used/$memory_total * 100}")

    # Disk Usage
    local disk_usage disk_percent
    disk_info=$(df / | tail -1)
    disk_usage=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
    disk_percent="$disk_usage"

    # System Temperature
    local temperature="N/A"
    if command -v vcgencmd >/dev/null 2>&1; then
        temperature=$(vcgencmd measure_temp 2>/dev/null | sed 's/temp=//' | sed 's/°C//' || echo "N/A")
    fi

    # Load Average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

    # Network Statistics
    local network_rx network_tx
    if [[ -f /proc/net/dev ]]; then
        network_stats=$(grep -E "(eth0|wlan0)" /proc/net/dev | head -1 | awk '{print $2, $10}')
        network_rx=$(echo "$network_stats" | awk '{print $1}')
        network_tx=$(echo "$network_stats" | awk '{print $2}')
    else
        network_rx=0
        network_tx=0
    fi

    # Create metrics JSON
    local metrics_json=$(cat << EOF
{
    "timestamp": "$timestamp",
    "cpu": {
        "usage_percent": $cpu_usage
    },
    "memory": {
        "total_bytes": $memory_total,
        "used_bytes": $memory_used,
        "usage_percent": $memory_percent
    },
    "disk": {
        "usage_percent": $disk_percent
    },
    "temperature": {
        "celsius": "$temperature"
    },
    "load": {
        "average_1min": $load_avg
    },
    "network": {
        "rx_bytes": $network_rx,
        "tx_bytes": $network_tx
    }
}
EOF
)

    # Append to metrics file
    echo "$metrics_json" >> "$metrics_file"

    # Check thresholds and generate alerts
    check_thresholds "$cpu_usage" "$memory_percent" "$disk_percent" "$temperature" "$load_avg"
}

# Check thresholds and generate alerts
check_thresholds() {
    local cpu_usage="$1"
    local memory_percent="$2"
    local disk_percent="$3"
    local temperature="$4"
    local load_avg="$5"

    local alerts=()

    # CPU threshold check
    if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        alerts+=("CPU usage is high: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)")
    fi

    # Memory threshold check
    if (( $(echo "$memory_percent > $MEMORY_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        alerts+=("Memory usage is high: ${memory_percent}% (threshold: ${MEMORY_THRESHOLD}%)")
    fi

    # Disk threshold check
    if [[ "$disk_percent" -gt "$DISK_THRESHOLD" ]]; then
        alerts+=("Disk usage is high: ${disk_percent}% (threshold: ${DISK_THRESHOLD}%)")
    fi

    # Temperature threshold check
    if [[ "$temperature" != "N/A" ]] && (( $(echo "$temperature > $TEMP_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        alerts+=("System temperature is high: ${temperature}°C (threshold: ${TEMP_THRESHOLD}°C)")
    fi

    # Load average threshold check
    if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        alerts+=("System load is high: $load_avg (threshold: $LOAD_THRESHOLD)")
    fi

    # Process alerts
    if [[ ${#alerts[@]} -gt 0 ]]; then
        for alert in "${alerts[@]}"; do
            generate_alert "THRESHOLD_EXCEEDED" "$alert"
        done
    fi
}

# Monitor services
monitor_services() {
    header "🔍 Monitoring Services"

    local services=("ssh" "ufw" "fail2ban")

    # Add WireGuard if VPN monitoring is enabled
    if [[ "${MONITOR_VPN:-true}" == "true" ]]; then
        services+=("wg-quick@wg0")
    fi

    local failed_services=()

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            success "$service: Running"
        else
            error "$service: Not running"
            failed_services+=("$service")
        fi
    done

    # Generate alerts for failed services
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        local failed_list=$(IFS=", "; echo "${failed_services[*]}")
        generate_alert "SERVICE_DOWN" "Critical services are down: $failed_list"
    fi
}

# Monitor network connectivity
monitor_network() {
    header "🌐 Monitoring Network Connectivity"

    # Test internet connectivity
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        success "Internet connectivity: Available"
    else
        error "Internet connectivity: Failed"
        generate_alert "NETWORK_DOWN" "Internet connectivity is not available"
    fi

    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        success "DNS resolution: Working"
    else
        warning "DNS resolution: Failed"
        generate_alert "DNS_FAILURE" "DNS resolution is not working properly"
    fi

    # Check VPN connectivity if enabled
    if [[ "${MONITOR_VPN:-true}" == "true" ]] && systemctl is-active --quiet "wg-quick@wg0" 2>/dev/null; then
        local vpn_peers
        vpn_peers=$(sudo wg show wg0 peers 2>/dev/null | wc -l || echo "0")
        info "VPN connected peers: $vpn_peers"
    fi
}

# Monitor security events
monitor_security() {
    header "🛡️ Monitoring Security Events"

    # Check for failed login attempts
    if [[ "${MONITOR_FAILED_LOGINS:-true}" == "true" ]]; then
        local failed_logins
        failed_logins=$(grep "Failed password" /var/log/auth.log 2>/dev/null | grep "$(date '+%b %d')" | wc -l || echo "0")

        if [[ "$failed_logins" -gt 10 ]]; then
            generate_alert "SECURITY_BREACH" "High number of failed login attempts today: $failed_logins"
        elif [[ "$failed_logins" -gt 0 ]]; then
            info "Failed login attempts today: $failed_logins"
        fi
    fi

    # Check fail2ban status
    if command -v fail2ban-client >/dev/null 2>&1; then
        local banned_ips
        banned_ips=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $4}' || echo "0")
        info "Currently banned IPs: $banned_ips"
    fi

    # Check for suspicious network activity
    local active_connections
    active_connections=$(ss -tupn | grep ESTAB | wc -l || echo "0")
    info "Active network connections: $active_connections"
}

# Generate alerts
generate_alert() {
    local alert_type="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local alert_id="alert-$(date '+%Y%m%d%H%M%S')-$$"

    # Create alert record
    local alert_file="$ALERTS_DIR/$alert_id.json"
    cat > "$alert_file" << EOF
{
    "id": "$alert_id",
    "timestamp": "$timestamp",
    "type": "$alert_type",
    "severity": "$(get_alert_severity "$alert_type")",
    "message": "$message",
    "hostname": "$(hostname)",
    "resolved": false
}
EOF

    # Log alert
    critical "ALERT [$alert_type]: $message"

    # Send notifications
    send_alert_notifications "$alert_type" "$message" "$timestamp"
}

# Get alert severity level
get_alert_severity() {
    local alert_type="$1"

    case $alert_type in
        "SERVICE_DOWN"|"NETWORK_DOWN"|"SECURITY_BREACH")
            echo "critical"
            ;;
        "THRESHOLD_EXCEEDED"|"DNS_FAILURE")
            echo "warning"
            ;;
        *)
            echo "info"
            ;;
    esac
}

# Send alert notifications
send_alert_notifications() {
    local alert_type="$1"
    local message="$2"
    local timestamp="$3"

    # Email notifications
    if [[ "${ENABLE_EMAIL_ALERTS:-false}" == "true" ]] && [[ -n "${ALERT_EMAIL:-}" ]]; then
        send_email_alert "$alert_type" "$message" "$timestamp"
    fi

    # Webhook notifications
    if [[ "${ENABLE_WEBHOOK_ALERTS:-false}" == "true" ]] && [[ -n "${WEBHOOK_URL:-}" ]]; then
        send_webhook_alert "$alert_type" "$message" "$timestamp"
    fi
}

# Send email alert
send_email_alert() {
    local alert_type="$1"
    local message="$2"
    local timestamp="$3"

    if command -v mail >/dev/null 2>&1; then
        echo "Pi Gateway Alert - $alert_type at $timestamp: $message" | \
            mail -s "Pi Gateway Alert: $alert_type" "$ALERT_EMAIL"
        info "Email alert sent to $ALERT_EMAIL"
    else
        warning "Mail command not available for email alerts"
    fi
}

# Send webhook alert
send_webhook_alert() {
    local alert_type="$1"
    local message="$2"
    local timestamp="$3"

    local webhook_payload=$(cat << EOF
{
    "alert_type": "$alert_type",
    "message": "$message",
    "timestamp": "$timestamp",
    "hostname": "$(hostname)",
    "severity": "$(get_alert_severity "$alert_type")"
}
EOF
)

    if command -v curl >/dev/null 2>&1; then
        if curl -X POST -H "Content-Type: application/json" \
               -d "$webhook_payload" \
               --connect-timeout "${WEBHOOK_TIMEOUT:-10}" \
               "$WEBHOOK_URL" >/dev/null 2>&1; then
            info "Webhook alert sent successfully"
        else
            warning "Failed to send webhook alert"
        fi
    else
        warning "curl not available for webhook alerts"
    fi
}

# Generate monitoring report
generate_report() {
    header "📊 Monitoring Report"

    local report_file="$METRICS_DIR/report-$(date '+%Y%m%d').txt"

    {
        echo "Pi Gateway Monitoring Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "=============================================="
        echo

        # System Overview
        echo "SYSTEM OVERVIEW:"
        echo "- Uptime: $(uptime -p)"
        echo "- Load Average: $(uptime | awk -F'load average:' '{print $2}')"

        if command -v vcgencmd >/dev/null 2>&1; then
            echo "- Temperature: $(vcgencmd measure_temp 2>/dev/null || echo 'N/A')"
        fi

        echo

        # Service Status
        echo "SERVICE STATUS:"
        for service in ssh ufw fail2ban wg-quick@wg0; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                echo "- $service: Running"
            else
                echo "- $service: Stopped"
            fi
        done

        echo

        # Recent Alerts
        echo "RECENT ALERTS (Last 24 hours):"
        if [[ -d "$ALERTS_DIR" ]]; then
            find "$ALERTS_DIR" -name "*.json" -newermt "24 hours ago" -exec basename {} .json \; | \
                head -5 | while read -r alert_id; do
                if [[ -f "$ALERTS_DIR/$alert_id.json" ]]; then
                    local alert_info
                    alert_info=$(grep -E "(timestamp|type|message)" "$ALERTS_DIR/$alert_id.json" | tr '\n' ' ')
                    echo "- $alert_info"
                fi
            done
        fi

        echo
        echo "End of Report"
        echo "=============================================="

    } > "$report_file"

    success "Report generated: $report_file"

    # Display report summary
    echo
    tail -20 "$report_file"
}

# Cleanup old metrics and alerts
cleanup_old_data() {
    local retention_days="${METRICS_RETENTION_DAYS:-30}"

    info "Cleaning up data older than $retention_days days"

    # Clean old metrics
    if [[ -d "$METRICS_DIR" ]]; then
        find "$METRICS_DIR" -name "*.json" -mtime +"$retention_days" -delete 2>/dev/null || true
    fi

    # Clean old alerts (keep for longer - 90 days)
    if [[ -d "$ALERTS_DIR" ]]; then
        find "$ALERTS_DIR" -name "*.json" -mtime +90 -delete 2>/dev/null || true
    fi

    # Rotate logs
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        sudo logrotate -f /etc/logrotate.d/pi-gateway-monitoring 2>/dev/null || true
    fi
}

# Install monitoring as a service
install_monitoring_service() {
    header "⚙️ Installing Monitoring Service"

    local service_file="/etc/systemd/system/pi-gateway-monitoring.service"
    local timer_file="/etc/systemd/system/pi-gateway-monitoring.timer"

    # Create service file
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Pi Gateway Monitoring System
After=network.target

[Service]
Type=oneshot
User=pi
Group=pi
ExecStart=$SCRIPT_DIR/$SCRIPT_NAME --run-monitoring
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create timer file for periodic execution
    sudo tee "$timer_file" > /dev/null << EOF
[Unit]
Description=Pi Gateway Monitoring Timer
Requires=pi-gateway-monitoring.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Create logrotate configuration
    sudo tee "/etc/logrotate.d/pi-gateway-monitoring" > /dev/null << EOF
$LOG_FILE {
    weekly
    rotate 4
    compress
    notifempty
    create 644 pi pi
    postrotate
        systemctl reload-or-restart pi-gateway-monitoring || true
    endscript
}
EOF

    # Enable and start the timer
    sudo systemctl daemon-reload
    sudo systemctl enable pi-gateway-monitoring.timer
    sudo systemctl start pi-gateway-monitoring.timer

    success "Monitoring service installed and started"
    info "Monitoring runs every 5 minutes"
    info "View logs: journalctl -u pi-gateway-monitoring -f"
}

# Run complete monitoring cycle
run_monitoring() {
    initialize_monitoring
    collect_system_metrics
    monitor_services
    monitor_network
    monitor_security
    cleanup_old_data
}

# Show monitoring status
show_status() {
    header "📊 Monitoring System Status"

    # Service status
    if systemctl is-active --quiet pi-gateway-monitoring.timer 2>/dev/null; then
        success "Monitoring timer: Active"
    else
        error "Monitoring timer: Inactive"
    fi

    # Recent alerts count
    local recent_alerts=0
    if [[ -d "$ALERTS_DIR" ]]; then
        recent_alerts=$(find "$ALERTS_DIR" -name "*.json" -newermt "24 hours ago" | wc -l)
    fi

    info "Alerts in last 24 hours: $recent_alerts"

    # Latest metrics
    if [[ -d "$METRICS_DIR" ]]; then
        local latest_metrics
        latest_metrics=$(find "$METRICS_DIR" -name "*.json" -type f | sort | tail -1)
        if [[ -n "$latest_metrics" ]]; then
            info "Latest metrics file: $(basename "$latest_metrics")"
        fi
    fi

    # Configuration status
    if [[ -f "$CONFIG_FILE" ]]; then
        success "Configuration: Found at $CONFIG_FILE"
    else
        warning "Configuration: Not found"
    fi
}

# Show help
show_help() {
    echo "Pi Gateway Advanced Monitoring System"
    echo
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Options:"
    echo "  --run-monitoring    Run complete monitoring cycle"
    echo "  --install-service   Install monitoring as a systemd service"
    echo "  --status           Show monitoring system status"
    echo "  --report           Generate monitoring report"
    echo "  --config           Show current configuration"
    echo "  --test-alerts      Test alert system"
    echo "  -h, --help         Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0") --run-monitoring     # Run monitoring once"
    echo "  $(basename "$0") --install-service    # Install as service"
    echo "  $(basename "$0") --status             # Check status"
    echo "  $(basename "$0") --report             # Generate report"
    echo
}

# Test alert system
test_alerts() {
    header "🧪 Testing Alert System"

    generate_alert "TEST" "This is a test alert from Pi Gateway monitoring system"
    success "Test alert generated"
}

# Show configuration
show_config() {
    header "⚙️ Current Configuration"

    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    else
        warning "Configuration file not found at $CONFIG_FILE"
        info "Run with --run-monitoring to create default configuration"
    fi
}

# Main execution
main() {
    case "${1:-}" in
        --run-monitoring)
            run_monitoring
            ;;
        --install-service)
            install_monitoring_service
            ;;
        --status)
            show_status
            ;;
        --report)
            generate_report
            ;;
        --config)
            show_config
            ;;
        --test-alerts)
            test_alerts
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
