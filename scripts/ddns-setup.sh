#!/bin/bash
#
# Pi Gateway - Dynamic DNS Setup
# Configure dynamic DNS for external access to homelab services
#

# Set strict error handling (without -u for array compatibility)
set -eo pipefail

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
readonly LOG_FILE="/tmp/pi-gateway-ddns-setup.log"
readonly CONFIG_BACKUP_DIR="/etc/pi-gateway/backups/ddns-$(date +%Y%m%d_%H%M%S)"

# DDNS configuration
readonly DDCLIENT_CONFIG="/etc/ddclient.conf"
readonly DDCLIENT_CACHE="/var/cache/ddclient/ddclient.cache"
readonly DDNS_LOG_FILE="/var/log/ddclient.log"
readonly DDNS_UPDATE_INTERVAL="${DDNS_UPDATE_INTERVAL:-300}"  # 5 minutes
readonly DDNS_CHECK_INTERVAL="${DDNS_CHECK_INTERVAL:-600}"   # 10 minutes

# Supported DDNS providers (bash 3.x compatible)
readonly SUPPORTED_PROVIDERS="duckdns noip cloudflare freedns namecheap"

# Get provider server for given provider name
get_provider_server() {
    local provider="$1"
    case "$provider" in
        "duckdns") echo "duckdns.org" ;;
        "noip") echo "dynupdate.no-ip.com" ;;
        "cloudflare") echo "cloudflare.com" ;;
        "freedns") echo "freedns.afraid.org" ;;
        "namecheap") echo "dynamicdns.park-your-domain.com" ;;
        *) echo "unknown" ;;
    esac
}

# Now set unbound variable checking
set -u

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
    echo -e "${BLUE}       Pi Gateway - Dynamic DNS Setup         ${NC}"
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
        echo -e "${PURPLE}   → All DDNS configuration will be simulated${NC}"
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

# Install ddclient
install_ddclient() {
    print_section "DDClient Installation"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "DDClient installation skipped in dry-run mode"
        return 0
    fi

    if ! command -v ddclient >/dev/null 2>&1; then
        info "Installing ddclient..."
        execute_command "apt update" "Update package repositories"
        execute_command "apt install -y ddclient" "Install ddclient"
        success "DDClient installed successfully"
    else
        success "DDClient is already installed"
    fi

    # Install additional tools
    execute_command "apt install -y curl wget" "Install network tools"
}

# Backup existing DDNS configuration
backup_ddns_config() {
    print_section "DDNS Configuration Backup"

    execute_command "mkdir -p '$CONFIG_BACKUP_DIR'" "Create backup directory"

    # Backup ddclient configuration
    if [[ -f "$DDCLIENT_CONFIG" ]]; then
        execute_command "cp '$DDCLIENT_CONFIG' '$CONFIG_BACKUP_DIR/ddclient.conf.backup'" "Backup ddclient configuration"
        success "DDClient configuration backed up"
    fi

    # Backup ddclient cache
    if [[ -f "$DDCLIENT_CACHE" ]]; then
        execute_command "cp '$DDCLIENT_CACHE' '$CONFIG_BACKUP_DIR/ddclient.cache.backup'" "Backup ddclient cache"
    fi

    success "DDNS configuration backed up: $CONFIG_BACKUP_DIR"
}

# Interactive DDNS provider selection
select_ddns_provider() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "duckdns"
        return 0
    fi

    echo
    echo -e "${BLUE}Available DDNS Providers:${NC}"
    echo -e "  ${YELLOW}1.${NC} DuckDNS (Free, easy setup)"
    echo -e "  ${YELLOW}2.${NC} No-IP (Free tier available)"
    echo -e "  ${YELLOW}3.${NC} Cloudflare (Free with domain)"
    echo -e "  ${YELLOW}4.${NC} FreeDNS (Free)"
    echo -e "  ${YELLOW}5.${NC} Namecheap (Paid domain required)"
    echo

    local choice
    read -p "Select DDNS provider (1-5): " choice

    case $choice in
        1) echo "duckdns" ;;
        2) echo "noip" ;;
        3) echo "cloudflare" ;;
        4) echo "freedns" ;;
        5) echo "namecheap" ;;
        *) echo "duckdns" ;; # Default
    esac
}

# Get provider credentials
get_provider_credentials() {
    local provider="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        case $provider in
            "duckdns")
                echo "your-domain.duckdns.org your-token-here"
                ;;
            "noip")
                echo "username:password your-hostname.ddns.net"
                ;;
            "cloudflare")
                echo "your-email your-api-key your-domain.com"
                ;;
            *)
                echo "hostname username password"
                ;;
        esac
        return 0
    fi

    echo
    case $provider in
        "duckdns")
            echo -e "${BLUE}DuckDNS Configuration:${NC}"
            echo -e "  1. Go to https://www.duckdns.org"
            echo -e "  2. Sign in and create a domain"
            echo -e "  3. Copy your token"
            echo
            local hostname token
            read -p "Enter your DuckDNS domain (e.g., myhome.duckdns.org): " hostname
            read -p "Enter your DuckDNS token: " token
            echo "$hostname $token"
            ;;
        "noip")
            echo -e "${BLUE}No-IP Configuration:${NC}"
            echo -e "  1. Go to https://www.noip.com"
            echo -e "  2. Create an account and hostname"
            echo -e "  3. Use your account credentials"
            echo
            local username password hostname
            read -p "Enter your No-IP username: " username
            read -s -p "Enter your No-IP password: " password
            echo
            read -p "Enter your No-IP hostname: " hostname
            echo "$username:$password $hostname"
            ;;
        "cloudflare")
            echo -e "${BLUE}Cloudflare Configuration:${NC}"
            echo -e "  1. Go to https://dash.cloudflare.com"
            echo -e "  2. Get your API key from Profile > API Tokens"
            echo -e "  3. Use your domain managed by Cloudflare"
            echo
            local email api_key domain
            read -p "Enter your Cloudflare email: " email
            read -p "Enter your Cloudflare API key: " api_key
            read -p "Enter your domain: " domain
            echo "$email $api_key $domain"
            ;;
        *)
            echo -e "${BLUE}Generic Configuration:${NC}"
            local hostname username password
            read -p "Enter hostname: " hostname
            read -p "Enter username: " username
            read -s -p "Enter password: " password
            echo
            echo "$hostname $username $password"
            ;;
    esac
}

# Configure DuckDNS
configure_duckdns() {
    local hostname="$1"
    local token="$2"

    execute_command "cat > '$DDCLIENT_CONFIG' << 'EOF'
# Pi Gateway DuckDNS Configuration
# Generated on $(date)

daemon=$DDNS_UPDATE_INTERVAL
syslog=yes
mail=root
mail-failure=root
pid=/var/run/ddclient.pid
ssl=yes
use=web, web=checkip.dyndns.com, web-skip='IP Address'

# DuckDNS configuration
protocol=duckdns
server=www.duckdns.org
login=nouser
password=$token
$hostname
EOF" "Create DuckDNS configuration"

    # Create DuckDNS update script
    execute_command "cat > '/usr/local/bin/duckdns-update' << 'EOF'
#!/bin/bash
# DuckDNS update script for Pi Gateway

DOMAIN=\"$hostname\"
TOKEN=\"$token\"
LOG_FILE=\"/var/log/duckdns.log\"

# Get current IP
CURRENT_IP=\$(curl -s https://ipinfo.io/ip)

# Update DuckDNS
RESPONSE=\$(curl -s \"https://www.duckdns.org/update?domains=\${DOMAIN}&token=\${TOKEN}&ip=\${CURRENT_IP}\")

# Log result
echo \"\$(date): IP \$CURRENT_IP - Response: \$RESPONSE\" >> \"\$LOG_FILE\"

if [[ \"\$RESPONSE\" == \"OK\" ]]; then
    echo \"DuckDNS update successful: \$CURRENT_IP\"
    exit 0
else
    echo \"DuckDNS update failed: \$RESPONSE\"
    exit 1
fi
EOF" "Create DuckDNS update script"

    execute_command "chmod +x '/usr/local/bin/duckdns-update'" "Make DuckDNS script executable"
}

# Configure No-IP
configure_noip() {
    local credentials="$1"
    local hostname="$2"

    execute_command "cat > '$DDCLIENT_CONFIG' << 'EOF'
# Pi Gateway No-IP Configuration
# Generated on $(date)

daemon=$DDNS_UPDATE_INTERVAL
syslog=yes
mail=root
mail-failure=root
pid=/var/run/ddclient.pid
ssl=yes
use=web, web=checkip.dyndns.com, web-skip='IP Address'

# No-IP configuration
protocol=noip
server=dynupdate.no-ip.com
login=$credentials
$hostname
EOF" "Create No-IP configuration"
}

# Configure Cloudflare
configure_cloudflare() {
    local email="$1"
    local api_key="$2"
    local domain="$3"

    execute_command "cat > '$DDCLIENT_CONFIG' << 'EOF'
# Pi Gateway Cloudflare Configuration
# Generated on $(date)

daemon=$DDNS_UPDATE_INTERVAL
syslog=yes
mail=root
mail-failure=root
pid=/var/run/ddclient.pid
ssl=yes
use=web, web=checkip.dyndns.com, web-skip='IP Address'

# Cloudflare configuration
protocol=cloudflare
server=www.cloudflare.com
login=$email
password=$api_key
zone=$domain
$domain
EOF" "Create Cloudflare configuration"
}

# Configure DDNS provider
configure_ddns_provider() {
    print_section "DDNS Provider Configuration"

    local provider
    provider=$(select_ddns_provider)
    info "Selected provider: $provider"

    local credentials
    credentials=$(get_provider_credentials "$provider")

    case $provider in
        "duckdns")
            local hostname token
            hostname=$(echo "$credentials" | awk '{print $1}')
            token=$(echo "$credentials" | awk '{print $2}')
            configure_duckdns "$hostname" "$token"
            ;;
        "noip")
            local auth hostname
            auth=$(echo "$credentials" | awk '{print $1}')
            hostname=$(echo "$credentials" | awk '{print $2}')
            configure_noip "$auth" "$hostname"
            ;;
        "cloudflare")
            local email api_key domain
            email=$(echo "$credentials" | awk '{print $1}')
            api_key=$(echo "$credentials" | awk '{print $2}')
            domain=$(echo "$credentials" | awk '{print $3}')
            configure_cloudflare "$email" "$api_key" "$domain"
            ;;
        *)
            error "Unsupported provider: $provider"
            exit 1
            ;;
    esac

    # Set proper permissions
    execute_command "chmod 600 '$DDCLIENT_CONFIG'" "Set ddclient config permissions"
    execute_command "chown root:root '$DDCLIENT_CONFIG'" "Set ddclient config ownership"

    success "DDNS provider configured: $provider"
}

# Create DDNS monitoring script
create_ddns_monitoring() {
    print_section "DDNS Monitoring Setup"

    execute_command "cat > '/usr/local/bin/ddns-monitor' << 'EOF'
#!/bin/bash
# Pi Gateway DDNS Monitoring Script

LOG_FILE=\"/var/log/ddns-monitor.log\"
DDNS_LOG=\"$DDNS_LOG_FILE\"
MAX_LOG_SIZE=10485760  # 10MB

# Function to log messages
log_message() {
    echo \"\$(date '+%Y-%m-%d %H:%M:%S') - \$1\" >> \"\$LOG_FILE\"
}

# Rotate logs if they get too large
rotate_logs() {
    if [[ -f \"\$LOG_FILE\" ]] && [[ \$(stat -c%s \"\$LOG_FILE\") -gt \$MAX_LOG_SIZE ]]; then
        mv \"\$LOG_FILE\" \"\${LOG_FILE}.old\"
        touch \"\$LOG_FILE\"
        log_message \"Log rotated\"
    fi
}

# Check DDNS service status
check_ddns_status() {
    if systemctl is-active ddclient >/dev/null 2>&1; then
        log_message \"DDClient service is running\"
        return 0
    else
        log_message \"ERROR: DDClient service is not running\"
        return 1
    fi
}

# Check for recent DDNS updates
check_recent_updates() {
    if [[ ! -f \"\$DDNS_LOG\" ]]; then
        log_message \"WARNING: DDNS log file not found\"
        return 1
    fi

    # Check for updates in the last hour
    recent_updates=\$(grep \"\$(date -d '1 hour ago' '+%Y-%m-%d %H')\" \"\$DDNS_LOG\" | wc -l)

    if [[ \$recent_updates -gt 0 ]]; then
        log_message \"Recent DDNS updates found: \$recent_updates\"
        return 0
    else
        log_message \"WARNING: No recent DDNS updates found\"
        return 1
    fi
}

# Get current public IP
get_current_ip() {
    local ip
    ip=\$(curl -s --connect-timeout 10 https://ipinfo.io/ip 2>/dev/null)

    if [[ -n \"\$ip\" ]] && [[ \"\$ip\" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\$ ]]; then
        echo \"\$ip\"
        return 0
    else
        log_message \"ERROR: Failed to get current public IP\"
        return 1
    fi
}

# Main monitoring function
main() {
    log_message \"Starting DDNS monitoring check\"

    rotate_logs

    local exit_code=0

    # Check service status
    if ! check_ddns_status; then
        exit_code=1
    fi

    # Check recent updates
    if ! check_recent_updates; then
        exit_code=1
    fi

    # Log current IP
    local current_ip
    if current_ip=\$(get_current_ip); then
        log_message \"Current public IP: \$current_ip\"
    else
        exit_code=1
    fi

    if [[ \$exit_code -eq 0 ]]; then
        log_message \"DDNS monitoring check completed successfully\"
    else
        log_message \"DDNS monitoring check completed with errors\"
    fi

    return \$exit_code
}

# Run monitoring
main \"\$@\"
EOF" "Create DDNS monitoring script"

    execute_command "chmod +x '/usr/local/bin/ddns-monitor'" "Make DDNS monitoring script executable"

    success "DDNS monitoring script created"
}

# Configure cron jobs for DDNS
configure_ddns_cron() {
    print_section "DDNS Cron Configuration"

    execute_command "cat > '/etc/cron.d/pi-gateway-ddns' << 'EOF'
# Pi Gateway DDNS Cron Jobs
# Monitor and maintain DDNS functionality

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Monitor DDNS every 10 minutes
*/10 * * * * root /usr/local/bin/ddns-monitor >/dev/null 2>&1

# Force DDNS update every 6 hours
0 */6 * * * root /usr/bin/ddclient -force >/dev/null 2>&1

# Weekly log cleanup (keep last 7 days)
0 2 * * 0 root find /var/log -name \"*ddns*\" -type f -mtime +7 -delete >/dev/null 2>&1
EOF" "Create DDNS cron jobs"

    execute_command "chmod 644 '/etc/cron.d/pi-gateway-ddns'" "Set cron file permissions"

    success "DDNS cron jobs configured"
}

# Configure ddclient service
configure_ddclient_service() {
    print_section "DDClient Service Configuration"

    # Create ddclient directories
    execute_command "mkdir -p '/var/cache/ddclient'" "Create ddclient cache directory"
    execute_command "mkdir -p '/var/log'" "Ensure log directory exists"
    execute_command "touch '$DDNS_LOG_FILE'" "Create ddclient log file"
    execute_command "chmod 644 '$DDNS_LOG_FILE'" "Set log file permissions"

    # Enable and start ddclient service
    execute_command "systemctl enable ddclient" "Enable ddclient service"

    if [[ "$DRY_RUN" == "false" ]]; then
        execute_command "systemctl restart ddclient" "Restart ddclient service"

        # Check service status
        sleep 2
        if systemctl is-active ddclient >/dev/null 2>&1; then
            success "DDClient service started successfully"
        else
            warning "DDClient service may have failed to start"
            warning "Check logs: journalctl -u ddclient"
        fi
    else
        success "DDClient service configuration skipped in dry-run mode"
    fi
}

# Test DDNS functionality
test_ddns_functionality() {
    print_section "DDNS Functionality Test"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "DDNS functionality test skipped in dry-run mode"
        return 0
    fi

    info "Testing DDNS update..."

    # Force an immediate update
    if execute_command "ddclient -daemon=0 -verbose -noquiet" "Force DDNS update"; then
        success "DDNS update test completed"
    else
        warning "DDNS update test may have failed"
        warning "Check configuration and try manual update"
    fi

    # Test monitoring script
    if execute_command "/usr/local/bin/ddns-monitor" "Test DDNS monitoring"; then
        success "DDNS monitoring test completed"
    else
        warning "DDNS monitoring test failed"
    fi
}

# Display DDNS information
display_ddns_info() {
    print_section "Dynamic DNS Information"

    echo
    echo -e "${GREEN}🌐 Dynamic DNS Setup Complete!${NC}"
    echo

    if [[ "$DRY_RUN" == "false" ]]; then
        local current_ip
        current_ip=$(curl -s https://ipinfo.io/ip 2>/dev/null || echo "Unable to detect")
        echo -e "${BLUE}Current Configuration:${NC}"
        echo -e "  ${YELLOW}Public IP:${NC} $current_ip"
        echo -e "  ${YELLOW}Update Interval:${NC} $DDNS_UPDATE_INTERVAL seconds"
        echo -e "  ${YELLOW}Check Interval:${NC} $DDNS_CHECK_INTERVAL seconds"
        echo
    fi

    echo -e "${BLUE}Service Management:${NC}"
    echo -e "  ${PURPLE}Status:${NC} sudo systemctl status ddclient"
    echo -e "  ${PURPLE}Start:${NC} sudo systemctl start ddclient"
    echo -e "  ${PURPLE}Stop:${NC} sudo systemctl stop ddclient"
    echo -e "  ${PURPLE}Restart:${NC} sudo systemctl restart ddclient"
    echo

    echo -e "${BLUE}Manual Operations:${NC}"
    echo -e "  ${PURPLE}Force update:${NC} sudo ddclient -force"
    echo -e "  ${PURPLE}Test update:${NC} sudo ddclient -daemon=0 -verbose"
    echo -e "  ${PURPLE}Check status:${NC} sudo /usr/local/bin/ddns-monitor"
    echo

    echo -e "${BLUE}Log Files:${NC}"
    echo -e "  ${PURPLE}DDClient:${NC} $DDNS_LOG_FILE"
    echo -e "  ${PURPLE}Monitoring:${NC} /var/log/ddns-monitor.log"
    echo -e "  ${PURPLE}System:${NC} journalctl -u ddclient"
    echo

    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo -e "  • DDNS updates your external IP address automatically"
    echo -e "  • Configure router port forwarding to use external access"
    echo -e "  • Monitor logs regularly for update failures"
    echo -e "  • Update credentials if provider tokens change"
    echo -e "  • Test connectivity after IP changes"
    echo

    success "Dynamic DNS setup completed successfully!"
}

# Main execution
main() {
    print_header

    log "INFO" "Starting Pi Gateway Dynamic DNS setup"

    # Initialize dry-run environment
    init_dry_run_environment

    # Pre-setup checks
    check_sudo

    # Setup process
    backup_ddns_config
    install_ddclient
    configure_ddns_provider
    create_ddns_monitoring
    configure_ddns_cron
    configure_ddclient_service
    test_ddns_functionality

    # Final information
    display_ddns_info

    log "INFO" "Pi Gateway Dynamic DNS setup completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi