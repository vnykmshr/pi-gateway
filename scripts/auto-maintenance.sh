#!/bin/bash
#
# Pi Gateway Automated Maintenance System
# Automated updates, system maintenance, and health optimization
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
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_FILE="/etc/pi-gateway/maintenance.conf"
readonly LOG_FILE="/var/log/pi-gateway/maintenance.log"
readonly BACKUP_DIR="/var/backups/pi-gateway"
readonly STATE_FILE="/var/lib/pi-gateway/maintenance-state.json"

# Default settings
readonly DEFAULT_AUTO_UPDATE_SYSTEM=true
readonly DEFAULT_AUTO_UPDATE_PI_GATEWAY=true
readonly DEFAULT_AUTO_CLEANUP=true
readonly DEFAULT_AUTO_BACKUP=true
readonly DEFAULT_UPDATE_HOUR=2
readonly DEFAULT_BACKUP_RETENTION_DAYS=14

# Maintenance configuration (loaded from config file)
AUTO_UPDATE_SYSTEM=${AUTO_UPDATE_SYSTEM:-$DEFAULT_AUTO_UPDATE_SYSTEM}
AUTO_UPDATE_PI_GATEWAY=${AUTO_UPDATE_PI_GATEWAY:-$DEFAULT_AUTO_UPDATE_PI_GATEWAY}
AUTO_CLEANUP=${AUTO_CLEANUP:-$DEFAULT_AUTO_CLEANUP}
AUTO_BACKUP=${AUTO_BACKUP:-$DEFAULT_AUTO_BACKUP}
UPDATE_HOUR=${UPDATE_HOUR:-$DEFAULT_UPDATE_HOUR}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-$DEFAULT_BACKUP_RETENTION_DAYS}

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

# Initialize maintenance system
initialize_maintenance() {
    # Create directories
    for dir in "$(dirname "$LOG_FILE")" "$BACKUP_DIR" "$(dirname "$STATE_FILE")"; do
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

    # Initialize state file
    if [[ ! -f "$STATE_FILE" ]]; then
        create_initial_state
    fi
}

# Create default configuration
create_default_config() {
    info "Creating default maintenance configuration"

    sudo mkdir -p "$(dirname "$CONFIG_FILE")"

    sudo tee "$CONFIG_FILE" > /dev/null << EOF
# Pi Gateway Automated Maintenance Configuration

# Update Settings
AUTO_UPDATE_SYSTEM=$DEFAULT_AUTO_UPDATE_SYSTEM
AUTO_UPDATE_PI_GATEWAY=$DEFAULT_AUTO_UPDATE_PI_GATEWAY
UPDATE_HOUR=$DEFAULT_UPDATE_HOUR
UPDATE_WEEKDAY=0  # Sunday (0-6, 0=Sunday)

# Maintenance Settings
AUTO_CLEANUP=$DEFAULT_AUTO_CLEANUP
AUTO_BACKUP=$DEFAULT_AUTO_BACKUP
BACKUP_RETENTION_DAYS=$DEFAULT_BACKUP_RETENTION_DAYS

# Cleanup Settings
CLEANUP_LOGS=true
CLEANUP_TEMP_FILES=true
CLEANUP_PACKAGE_CACHE=true
CLEANUP_OLD_KERNELS=true

# Backup Settings
BACKUP_CONFIGURATIONS=true
BACKUP_LOGS=true
BACKUP_KEYS=true
COMPRESS_BACKUPS=true

# Security Settings
AUTO_SECURITY_UPDATES=true
UPDATE_FAIL2BAN_RULES=true
REFRESH_SSH_KEYS=false

# Performance Settings
OPTIMIZE_MEMORY=true
OPTIMIZE_DISK=true
DEFRAGMENT_LOGS=true

# Notification Settings
SEND_SUCCESS_NOTIFICATIONS=false
SEND_FAILURE_NOTIFICATIONS=true
EMAIL_REPORTS=false
NOTIFICATION_EMAIL=""

# Safety Settings
MAX_DISK_USAGE_PERCENT=95
MIN_FREE_MEMORY_MB=100
REQUIRE_CONFIRMATION=false
DRY_RUN_MODE=false
EOF

    sudo chown root:pi "$CONFIG_FILE"
    sudo chmod 640 "$CONFIG_FILE"

    success "Default configuration created at $CONFIG_FILE"
}

# Create initial state file
create_initial_state() {
    local initial_state=$(cat << EOF
{
    "last_update_check": "never",
    "last_system_update": "never",
    "last_pi_gateway_update": "never",
    "last_cleanup": "never",
    "last_backup": "never",
    "maintenance_runs": 0,
    "last_reboot": "never",
    "update_failures": 0,
    "cleanup_failures": 0,
    "backup_failures": 0
}
EOF
)

    echo "$initial_state" > "$STATE_FILE"
    chmod 644 "$STATE_FILE"
}

# Update state file
update_state() {
    local key="$1"
    local value="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Create temporary state file with updated value
    local temp_state=$(mktemp)

    if [[ -f "$STATE_FILE" ]]; then
        jq --arg key "$key" --arg value "$value" --arg timestamp "$timestamp" \
           '.[$key] = $value | .last_update = $timestamp' \
           "$STATE_FILE" > "$temp_state" 2>/dev/null || {
            # Fallback if jq is not available
            create_initial_state
            cp "$STATE_FILE" "$temp_state"
        }
    else
        create_initial_state
        cp "$STATE_FILE" "$temp_state"
    fi

    mv "$temp_state" "$STATE_FILE"
}

# System health check
perform_health_check() {
    header "🏥 System Health Check"

    local health_issues=()

    # Check disk space
    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

    if [[ "$disk_usage" -gt "${MAX_DISK_USAGE_PERCENT:-95}" ]]; then
        health_issues+=("Disk usage is critically high: ${disk_usage}%")
        error "Critical: Disk usage is ${disk_usage}%"
    elif [[ "$disk_usage" -gt 80 ]]; then
        warning "Disk usage is high: ${disk_usage}%"
    else
        success "Disk usage is healthy: ${disk_usage}%"
    fi

    # Check memory
    local memory_free
    memory_free=$(free -m | grep '^Mem:' | awk '{print $7}')

    if [[ "$memory_free" -lt "${MIN_FREE_MEMORY_MB:-100}" ]]; then
        health_issues+=("Free memory is low: ${memory_free}MB")
        warning "Low free memory: ${memory_free}MB"
    else
        success "Memory usage is healthy: ${memory_free}MB free"
    fi

    # Check system temperature (if available)
    if command -v vcgencmd >/dev/null 2>&1; then
        local temp
        temp=$(vcgencmd measure_temp 2>/dev/null | sed 's/temp=//' | sed 's/°C//' || echo "N/A")

        if [[ "$temp" != "N/A" ]]; then
            if (( $(echo "$temp > 80" | bc -l 2>/dev/null || echo "0") )); then
                health_issues+=("System temperature is high: ${temp}°C")
                warning "High temperature: ${temp}°C"
            else
                success "Temperature is normal: ${temp}°C"
            fi
        fi
    fi

    # Check service status
    local critical_services=("ssh" "ufw")
    for service in "${critical_services[@]}"; do
        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            health_issues+=("Critical service $service is not running")
            error "Service $service is not running"
        else
            success "Service $service is running"
        fi
    done

    # Return health status
    if [[ ${#health_issues[@]} -gt 0 ]]; then
        error "Health check found ${#health_issues[@]} issues"
        return 1
    else
        success "System health check passed"
        return 0
    fi
}

# System updates
perform_system_updates() {
    header "📦 System Updates"

    if [[ "${AUTO_UPDATE_SYSTEM:-true}" != "true" ]]; then
        info "System updates disabled in configuration"
        return 0
    fi

    local update_needed=false

    # Update package lists
    info "Updating package lists..."
    if sudo apt update 2>/dev/null; then
        success "Package lists updated"
    else
        error "Failed to update package lists"
        update_state "update_failures" "$(($(get_state_value "update_failures") + 1))"
        return 1
    fi

    # Check for available upgrades
    local upgradable_packages
    upgradable_packages=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")

    if [[ "$upgradable_packages" -gt 0 ]]; then
        info "Found $upgradable_packages packages to upgrade"
        update_needed=true

        # Perform security updates first
        if [[ "${AUTO_SECURITY_UPDATES:-true}" == "true" ]]; then
            info "Installing security updates..."
            if sudo unattended-upgrade -d 2>/dev/null || sudo apt upgrade -y; then
                success "Security updates installed"
            else
                warning "Some security updates may have failed"
            fi
        fi

        # Perform full system upgrade
        info "Performing system upgrade..."
        if sudo apt upgrade -y; then
            success "System upgrade completed"
            update_state "last_system_update" "$(date '+%Y-%m-%d %H:%M:%S')"
        else
            error "System upgrade failed"
            update_state "update_failures" "$(($(get_state_value "update_failures") + 1))"
            return 1
        fi

        # Clean up
        info "Cleaning up packages..."
        sudo apt autoremove -y >/dev/null 2>&1
        sudo apt autoclean >/dev/null 2>&1

    else
        success "System is up to date"
    fi

    # Check if reboot is required
    if [[ -f /var/run/reboot-required ]]; then
        warning "System reboot is required for some updates"
        info "Reboot will be scheduled during next maintenance window"
        echo "reboot-required" > /tmp/pi-gateway-reboot-required
    fi

    update_state "last_update_check" "$(date '+%Y-%m-%d %H:%M:%S')"
    return 0
}

# Pi Gateway updates
perform_pi_gateway_updates() {
    header "🚀 Pi Gateway Updates"

    if [[ "${AUTO_UPDATE_PI_GATEWAY:-true}" != "true" ]]; then
        info "Pi Gateway updates disabled in configuration"
        return 0
    fi

    cd "$PROJECT_ROOT"

    # Check for updates
    info "Checking for Pi Gateway updates..."

    local current_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    # Fetch latest changes
    if git fetch origin main 2>/dev/null; then
        local latest_commit
        latest_commit=$(git rev-parse origin/main 2>/dev/null || echo "unknown")

        if [[ "$current_commit" != "$latest_commit" ]]; then
            info "Pi Gateway updates available"

            # Create backup before updating
            if [[ "${AUTO_BACKUP:-true}" == "true" ]]; then
                create_configuration_backup "pre-update"
            fi

            # Pull updates
            if git pull origin main; then
                success "Pi Gateway updated successfully"
                update_state "last_pi_gateway_update" "$(date '+%Y-%m-%d %H:%M:%S')"

                # Run any update scripts if they exist
                if [[ -f "$PROJECT_ROOT/scripts/post-update.sh" ]]; then
                    info "Running post-update scripts..."
                    bash "$PROJECT_ROOT/scripts/post-update.sh"
                fi

            else
                error "Failed to update Pi Gateway"
                return 1
            fi
        else
            success "Pi Gateway is up to date"
        fi
    else
        warning "Could not check for Pi Gateway updates (no internet or git repository)"
    fi

    return 0
}

# System cleanup
perform_system_cleanup() {
    header "🧹 System Cleanup"

    if [[ "${AUTO_CLEANUP:-true}" != "true" ]]; then
        info "System cleanup disabled in configuration"
        return 0
    fi

    local cleanup_freed=0

    # Clean package cache
    if [[ "${CLEANUP_PACKAGE_CACHE:-true}" == "true" ]]; then
        info "Cleaning package cache..."
        local cache_before
        cache_before=$(du -sm /var/cache/apt/archives 2>/dev/null | cut -f1 || echo "0")

        sudo apt autoclean >/dev/null 2>&1
        sudo apt clean >/dev/null 2>&1

        local cache_after
        cache_after=$(du -sm /var/cache/apt/archives 2>/dev/null | cut -f1 || echo "0")
        local cache_freed=$((cache_before - cache_after))
        cleanup_freed=$((cleanup_freed + cache_freed))

        success "Package cache cleaned (freed ${cache_freed}MB)"
    fi

    # Clean temporary files
    if [[ "${CLEANUP_TEMP_FILES:-true}" == "true" ]]; then
        info "Cleaning temporary files..."
        local temp_before
        temp_before=$(du -sm /tmp 2>/dev/null | cut -f1 || echo "0")

        sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
        sudo find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

        local temp_after
        temp_after=$(du -sm /tmp 2>/dev/null | cut -f1 || echo "0")
        local temp_freed=$((temp_before - temp_after))
        cleanup_freed=$((cleanup_freed + temp_freed))

        success "Temporary files cleaned (freed ${temp_freed}MB)"
    fi

    # Clean old logs
    if [[ "${CLEANUP_LOGS:-true}" == "true" ]]; then
        info "Cleaning old log files..."

        # Use journalctl to clean systemd logs
        sudo journalctl --vacuum-time=2weeks >/dev/null 2>&1 || true

        # Clean old Pi Gateway logs
        find "/var/log/pi-gateway" -name "*.log.*" -mtime +7 -delete 2>/dev/null || true

        success "Log files cleaned"
    fi

    # Clean old kernels (Debian/Ubuntu)
    if [[ "${CLEANUP_OLD_KERNELS:-true}" == "true" ]] && command -v apt >/dev/null 2>&1; then
        info "Cleaning old kernel packages..."

        # Remove old kernel packages (keep current + 1 previous)
        sudo apt autoremove --purge -y >/dev/null 2>&1 || true

        success "Old kernels cleaned"
    fi

    # Defragment logs if needed
    if [[ "${DEFRAGMENT_LOGS:-true}" == "true" ]]; then
        info "Optimizing log files..."

        # Rotate and compress logs
        sudo logrotate -f /etc/logrotate.conf >/dev/null 2>&1 || true

        success "Log files optimized"
    fi

    success "System cleanup completed (total freed: ${cleanup_freed}MB)"
    update_state "last_cleanup" "$(date '+%Y-%m-%d %H:%M:%S')"

    return 0
}

# Configuration backup
create_configuration_backup() {
    local backup_type="${1:-scheduled}"

    header "💾 Configuration Backup"

    if [[ "${AUTO_BACKUP:-true}" != "true" ]] && [[ "$backup_type" == "scheduled" ]]; then
        info "Automated backup disabled in configuration"
        return 0
    fi

    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="pi-gateway-${backup_type}-${timestamp}"
    local backup_file="$BACKUP_DIR/${backup_name}.tar.gz"

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Create temporary directory for backup staging
    local temp_backup_dir=$(mktemp -d)

    # Backup configurations
    if [[ "${BACKUP_CONFIGURATIONS:-true}" == "true" ]]; then
        info "Backing up configurations..."

        # Pi Gateway configurations
        if [[ -d "/etc/pi-gateway" ]]; then
            mkdir -p "$temp_backup_dir/pi-gateway"
            cp -r /etc/pi-gateway/* "$temp_backup_dir/pi-gateway/" 2>/dev/null || true
        fi

        # SSH configuration
        if [[ -d "/etc/ssh" ]]; then
            mkdir -p "$temp_backup_dir/ssh"
            cp /etc/ssh/sshd_config "$temp_backup_dir/ssh/" 2>/dev/null || true
        fi

        # WireGuard configuration
        if [[ -d "/etc/wireguard" ]]; then
            mkdir -p "$temp_backup_dir/wireguard"
            cp -r /etc/wireguard/* "$temp_backup_dir/wireguard/" 2>/dev/null || true
        fi

        # Firewall configuration
        if [[ -d "/etc/ufw" ]]; then
            mkdir -p "$temp_backup_dir/ufw"
            cp -r /etc/ufw/* "$temp_backup_dir/ufw/" 2>/dev/null || true
        fi

        # Fail2ban configuration
        if [[ -d "/etc/fail2ban" ]]; then
            mkdir -p "$temp_backup_dir/fail2ban"
            cp -r /etc/fail2ban/jail.local "$temp_backup_dir/fail2ban/" 2>/dev/null || true
        fi
    fi

    # Backup SSH keys
    if [[ "${BACKUP_KEYS:-true}" == "true" ]]; then
        info "Backing up SSH keys..."

        if [[ -d "/home/pi/.ssh" ]]; then
            mkdir -p "$temp_backup_dir/user-ssh"
            cp -r /home/pi/.ssh/* "$temp_backup_dir/user-ssh/" 2>/dev/null || true
        fi
    fi

    # Backup recent logs
    if [[ "${BACKUP_LOGS:-true}" == "true" ]]; then
        info "Backing up recent logs..."

        mkdir -p "$temp_backup_dir/logs"

        # Pi Gateway logs
        if [[ -d "/var/log/pi-gateway" ]]; then
            cp -r /var/log/pi-gateway/* "$temp_backup_dir/logs/" 2>/dev/null || true
        fi

        # System logs (last 7 days)
        journalctl --since "7 days ago" > "$temp_backup_dir/logs/system-journal.log" 2>/dev/null || true
    fi

    # Create backup metadata
    cat > "$temp_backup_dir/backup-info.json" << EOF
{
    "backup_type": "$backup_type",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "hostname": "$(hostname)",
    "pi_gateway_version": "$(cd "$PROJECT_ROOT" && git describe --tags 2>/dev/null || echo "unknown")",
    "system_info": {
        "os": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"')",
        "kernel": "$(uname -r)",
        "uptime": "$(uptime -p)"
    }
}
EOF

    # Create compressed backup
    info "Creating compressed backup..."

    if [[ "${COMPRESS_BACKUPS:-true}" == "true" ]]; then
        tar -czf "$backup_file" -C "$temp_backup_dir" . 2>/dev/null
    else
        tar -cf "${backup_file%.gz}" -C "$temp_backup_dir" . 2>/dev/null
        backup_file="${backup_file%.gz}"
    fi

    # Cleanup temporary directory
    rm -rf "$temp_backup_dir"

    # Verify backup
    if [[ -f "$backup_file" ]]; then
        local backup_size
        backup_size=$(du -h "$backup_file" | cut -f1)
        success "Backup created: $backup_file ($backup_size)"
        update_state "last_backup" "$(date '+%Y-%m-%d %H:%M:%S')"
    else
        error "Failed to create backup"
        update_state "backup_failures" "$(($(get_state_value "backup_failures") + 1))"
        return 1
    fi

    # Clean old backups
    if [[ "$backup_type" == "scheduled" ]]; then
        cleanup_old_backups
    fi

    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    info "Cleaning up old backups..."

    local retention_days="${BACKUP_RETENTION_DAYS:-14}"

    find "$BACKUP_DIR" -name "pi-gateway-*.tar.gz" -mtime +"$retention_days" -delete 2>/dev/null || true
    find "$BACKUP_DIR" -name "pi-gateway-*.tar" -mtime +"$retention_days" -delete 2>/dev/null || true

    local remaining_backups
    remaining_backups=$(find "$BACKUP_DIR" -name "pi-gateway-*.tar*" | wc -l)

    info "Backup cleanup completed ($remaining_backups backups retained)"
}

# Performance optimization
perform_optimization() {
    header "⚡ Performance Optimization"

    # Memory optimization
    if [[ "${OPTIMIZE_MEMORY:-true}" == "true" ]]; then
        info "Optimizing memory usage..."

        # Clear page cache
        sudo sync
        echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true

        # Optimize swappiness for SSD/SD card
        echo 10 | sudo tee /proc/sys/vm/swappiness >/dev/null 2>&1 || true

        success "Memory optimization completed"
    fi

    # Disk optimization
    if [[ "${OPTIMIZE_DISK:-true}" == "true" ]]; then
        info "Optimizing disk performance..."

        # Trim SSD (if applicable)
        if command -v fstrim >/dev/null 2>&1; then
            sudo fstrim -v / >/dev/null 2>&1 || true
        fi

        success "Disk optimization completed"
    fi
}

# Get state value
get_state_value() {
    local key="$1"
    local default="${2:-0}"

    if [[ -f "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
        jq -r ".${key} // \"${default}\"" "$STATE_FILE" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# Send notification
send_notification() {
    local subject="$1"
    local message="$2"
    local level="${3:-info}"

    # Log notification
    log "NOTIFICATION" "$subject: $message"

    # Email notification (if configured)
    if [[ "${EMAIL_REPORTS:-false}" == "true" ]] && [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
        if command -v mail >/dev/null 2>&1; then
            echo "$message" | mail -s "Pi Gateway: $subject" "$NOTIFICATION_EMAIL" 2>/dev/null || true
        fi
    fi
}

# Run complete maintenance cycle
run_maintenance() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')

    header "🔧 Pi Gateway Automated Maintenance"
    info "Starting maintenance cycle at $start_time"

    initialize_maintenance

    local maintenance_success=true
    local maintenance_summary=()

    # Health check first
    if perform_health_check; then
        maintenance_summary+=("Health check: PASSED")
    else
        maintenance_summary+=("Health check: FAILED")
        maintenance_success=false
    fi

    # System updates
    if perform_system_updates; then
        maintenance_summary+=("System updates: COMPLETED")
    else
        maintenance_summary+=("System updates: FAILED")
        maintenance_success=false
    fi

    # Pi Gateway updates
    if perform_pi_gateway_updates; then
        maintenance_summary+=("Pi Gateway updates: COMPLETED")
    else
        maintenance_summary+=("Pi Gateway updates: FAILED")
        maintenance_success=false
    fi

    # System cleanup
    if perform_system_cleanup; then
        maintenance_summary+=("System cleanup: COMPLETED")
    else
        maintenance_summary+=("System cleanup: FAILED")
        maintenance_success=false
    fi

    # Configuration backup
    if create_configuration_backup "scheduled"; then
        maintenance_summary+=("Backup: COMPLETED")
    else
        maintenance_summary+=("Backup: FAILED")
        maintenance_success=false
    fi

    # Performance optimization
    if perform_optimization; then
        maintenance_summary+=("Optimization: COMPLETED")
    else
        maintenance_summary+=("Optimization: FAILED")
        maintenance_success=false
    fi

    # Update maintenance counter
    local maintenance_runs
    maintenance_runs=$(($(get_state_value "maintenance_runs") + 1))
    update_state "maintenance_runs" "$maintenance_runs"

    # Generate summary
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local summary_message="Maintenance cycle #$maintenance_runs completed at $end_time"

    header "📊 Maintenance Summary"

    for item in "${maintenance_summary[@]}"; do
        if [[ "$item" =~ "FAILED" ]]; then
            error "$item"
        else
            success "$item"
        fi
    done

    if [[ "$maintenance_success" == "true" ]]; then
        success "All maintenance tasks completed successfully"

        # Send success notification if enabled
        if [[ "${SEND_SUCCESS_NOTIFICATIONS:-false}" == "true" ]]; then
            send_notification "Maintenance Completed" "$summary_message" "success"
        fi
    else
        error "Some maintenance tasks failed"

        # Send failure notification
        if [[ "${SEND_FAILURE_NOTIFICATIONS:-true}" == "true" ]]; then
            send_notification "Maintenance Issues" "Some maintenance tasks failed. Check logs for details." "error"
        fi
    fi

    info "Maintenance cycle completed at $end_time"

    # Handle reboot if required
    if [[ -f /tmp/pi-gateway-reboot-required ]]; then
        warning "System reboot is required"

        if [[ "${REQUIRE_CONFIRMATION:-false}" != "true" ]]; then
            info "Scheduling reboot for 2 AM tomorrow"
            echo "sudo reboot" | sudo at 02:00 tomorrow 2>/dev/null || true
            rm -f /tmp/pi-gateway-reboot-required
        fi
    fi
}

# Install maintenance as a service
install_maintenance_service() {
    header "⚙️ Installing Maintenance Service"

    local service_file="/etc/systemd/system/pi-gateway-maintenance.service"
    local timer_file="/etc/systemd/system/pi-gateway-maintenance.timer"

    # Create service file
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Pi Gateway Automated Maintenance
After=network.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=$SCRIPT_DIR/$(basename "$0") --run-maintenance
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create timer file
    sudo tee "$timer_file" > /dev/null << EOF
[Unit]
Description=Pi Gateway Maintenance Timer
Requires=pi-gateway-maintenance.service

[Timer]
OnCalendar=Sun ${UPDATE_HOUR:-2}:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start the timer
    sudo systemctl daemon-reload
    sudo systemctl enable pi-gateway-maintenance.timer
    sudo systemctl start pi-gateway-maintenance.timer

    success "Maintenance service installed and scheduled"
    info "Maintenance runs weekly on Sunday at ${UPDATE_HOUR:-2}:00 AM"
    info "View logs: journalctl -u pi-gateway-maintenance -f"
}

# Show maintenance status
show_status() {
    header "📊 Maintenance System Status"

    # Service status
    if systemctl is-active --quiet pi-gateway-maintenance.timer 2>/dev/null; then
        success "Maintenance timer: Active"

        local next_run
        next_run=$(systemctl list-timers pi-gateway-maintenance.timer --no-pager | grep "pi-gateway-maintenance.timer" | awk '{print $1, $2}' || echo "Unknown")
        info "Next scheduled run: $next_run"
    else
        error "Maintenance timer: Inactive"
    fi

    # Load state information
    if [[ -f "$STATE_FILE" ]]; then
        local last_update_check last_backup maintenance_runs
        last_update_check=$(get_state_value "last_update_check" "never")
        last_backup=$(get_state_value "last_backup" "never")
        maintenance_runs=$(get_state_value "maintenance_runs" "0")

        info "Last update check: $last_update_check"
        info "Last backup: $last_backup"
        info "Total maintenance runs: $maintenance_runs"
    fi

    # Configuration status
    if [[ -f "$CONFIG_FILE" ]]; then
        success "Configuration: Found at $CONFIG_FILE"
    else
        warning "Configuration: Not found"
    fi

    # Backup status
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_count backup_size
        backup_count=$(find "$BACKUP_DIR" -name "*.tar*" | wc -l)
        backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")
        info "Backups: $backup_count files ($backup_size total)"
    fi
}

# Show help
show_help() {
    echo "Pi Gateway Automated Maintenance System"
    echo
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Options:"
    echo "  --run-maintenance     Run complete maintenance cycle"
    echo "  --install-service     Install maintenance as a systemd service"
    echo "  --status             Show maintenance system status"
    echo "  --health-check       Perform system health check only"
    echo "  --backup             Create configuration backup"
    echo "  --cleanup            Run system cleanup only"
    echo "  --updates            Check and install updates only"
    echo "  --config             Show current configuration"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0") --run-maintenance   # Run full maintenance"
    echo "  $(basename "$0") --install-service   # Install as service"
    echo "  $(basename "$0") --backup            # Create backup"
    echo "  $(basename "$0") --health-check      # Check system health"
    echo
}

# Show configuration
show_config() {
    header "⚙️ Current Configuration"

    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    else
        warning "Configuration file not found at $CONFIG_FILE"
        info "Run with --run-maintenance to create default configuration"
    fi
}

# Main execution
main() {
    case "${1:-}" in
        --run-maintenance)
            run_maintenance
            ;;
        --install-service)
            install_maintenance_service
            ;;
        --status)
            show_status
            ;;
        --health-check)
            initialize_maintenance
            perform_health_check
            ;;
        --backup)
            initialize_maintenance
            create_configuration_backup "manual"
            ;;
        --cleanup)
            initialize_maintenance
            perform_system_cleanup
            ;;
        --updates)
            initialize_maintenance
            perform_system_updates
            perform_pi_gateway_updates
            ;;
        --config)
            show_config
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
