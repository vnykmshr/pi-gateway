#!/bin/bash
#
# Pi Gateway CLI - User-Friendly Command Line Interface
# Simple interface for common Pi Gateway operations
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
readonly VERSION="1.1.0"

# Logging functions
success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

error() {
    echo -e "  ${RED}✗${NC} $1"
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

header() {
    echo
    echo -e "${CYAN}$1${NC}"
    echo
}

# Print header
print_header() {
    clear
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                      ${WHITE}Pi Gateway CLI${NC}${BLUE}                        ${NC}"
    echo -e "${BLUE}                    ${CYAN}v${VERSION} - Easy Management${NC}${BLUE}                   ${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo
}

# Show help
show_help() {
    echo "Pi Gateway CLI - User-Friendly Management Interface"
    echo
    echo "Usage: $(basename "$0") [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  status          Show system and service status"
    echo "  setup           Run initial Pi Gateway setup"
    echo "  vpn             VPN management (add/remove/list clients)"
    echo "  backup          Configuration backup and restore"
    echo "  logs            View system and service logs"
    echo "  security        Security monitoring and management"
    echo "  update          Update Pi Gateway and system"
    echo "  help            Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0") status          # Quick status overview"
    echo "  $(basename "$0") vpn add laptop  # Add VPN client 'laptop'"
    echo "  $(basename "$0") backup create   # Create configuration backup"
    echo "  $(basename "$0") logs ssh        # Show SSH logs"
    echo
    echo "For detailed help on a command:"
    echo "  $(basename "$0") [command] --help"
    echo
}

# Status command
cmd_status() {
    print_header
    echo -e "${CYAN}📊 Pi Gateway System Status${NC}"
    echo

    # Quick system info
    echo -e "${BLUE}System Information:${NC}"
    info "Hostname: $(hostname)"
    info "Uptime: $(uptime -p)"
    info "Load: $(uptime | awk -F'load average:' '{print $2}')"
    info "Temperature: $(vcgencmd measure_temp 2>/dev/null || echo 'N/A')"
    echo

    # Run detailed status if available
    if [[ -f "$SCRIPT_DIR/service-status.sh" ]]; then
        "$SCRIPT_DIR/service-status.sh"
    else
        warning "Detailed status script not found"
        info "Run basic service checks..."

        # Basic service checks
        echo -e "${BLUE}Core Services:${NC}"
        for service in ssh ufw fail2ban; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                success "$service: Active"
            else
                error "$service: Inactive"
            fi
        done

        # Check WireGuard
        if systemctl is-active --quiet "wg-quick@wg0" 2>/dev/null; then
            success "WireGuard VPN: Active"
        else
            warning "WireGuard VPN: Inactive"
        fi
    fi
}

# VPN management
cmd_vpn() {
    local action="${1:-}"

    case $action in
        add)
            local client_name="${2:-}"
            if [[ -z "$client_name" ]]; then
                error "Client name required"
                echo "Usage: $(basename "$0") vpn add <client-name>"
                exit 1
            fi

            header "🔐 Adding VPN Client: $client_name"

            if [[ -f "$SCRIPT_DIR/vpn-client-add.sh" ]]; then
                "$SCRIPT_DIR/vpn-client-add.sh" "$client_name"
            else
                warning "VPN client management script not found"
                info "Manual client addition required"
            fi
            ;;

        remove|rm)
            local client_name="${2:-}"
            if [[ -z "$client_name" ]]; then
                error "Client name required"
                echo "Usage: $(basename "$0") vpn remove <client-name>"
                exit 1
            fi

            header "🗑️  Removing VPN Client: $client_name"

            if [[ -f "$SCRIPT_DIR/vpn-client-remove.sh" ]]; then
                "$SCRIPT_DIR/vpn-client-remove.sh" "$client_name"
            else
                warning "VPN client management script not found"
                info "Manual client removal required"
            fi
            ;;

        list|ls)
            header "📋 VPN Client Status"

            if command -v wg >/dev/null 2>&1; then
                if sudo wg show wg0 >/dev/null 2>&1; then
                    echo -e "${BLUE}WireGuard Interface:${NC}"
                    sudo wg show wg0
                    echo

                    local peer_count
                    peer_count=$(sudo wg show wg0 peers 2>/dev/null | wc -l || echo "0")
                    info "Total connected peers: $peer_count"
                else
                    warning "WireGuard interface wg0 not active"
                fi
            else
                error "WireGuard not installed"
            fi
            ;;

        status)
            header "🔍 VPN Service Status"

            # Check WireGuard service
            if systemctl is-active --quiet "wg-quick@wg0" 2>/dev/null; then
                success "WireGuard service: Active"
            else
                error "WireGuard service: Inactive"
            fi

            # Check firewall rules
            if command -v ufw >/dev/null 2>&1; then
                if sudo ufw status | grep -q "51820"; then
                    success "Firewall: VPN port open"
                else
                    warning "Firewall: VPN port may be blocked"
                fi
            fi

            # Show interface info
            if command -v wg >/dev/null 2>&1 && sudo wg show wg0 >/dev/null 2>&1; then
                echo
                echo -e "${BLUE}Interface Details:${NC}"
                sudo wg show wg0
            fi
            ;;

        --help)
            echo "VPN Management Commands:"
            echo
            echo "  add <name>      Add new VPN client"
            echo "  remove <name>   Remove VPN client"
            echo "  list            List active VPN connections"
            echo "  status          Show VPN service status"
            echo
            ;;

        *)
            error "Unknown VPN command: $action"
            echo "Available commands: add, remove, list, status"
            echo "Use '$(basename "$0") vpn --help' for details"
            exit 1
            ;;
    esac
}

# Backup management
cmd_backup() {
    local action="${1:-}"

    case $action in
        create|backup)
            header "📦 Creating Configuration Backup"

            if [[ -f "$SCRIPT_DIR/backup-config.sh" ]]; then
                "$SCRIPT_DIR/backup-config.sh" backup
            else
                warning "Backup script not found"
                info "Creating basic backup..."

                local backup_name="pi-gateway-backup-$(date +%Y%m%d-%H%M%S)"
                local backup_dir="/tmp/$backup_name"

                mkdir -p "$backup_dir"

                # Backup key configurations
                [[ -d /etc/ssh ]] && cp -r /etc/ssh "$backup_dir/"
                [[ -d /etc/wireguard ]] && cp -r /etc/wireguard "$backup_dir/"
                [[ -f /etc/ufw/user.rules ]] && cp /etc/ufw/user.rules "$backup_dir/"

                tar -czf "${backup_name}.tar.gz" -C /tmp "$backup_name"
                rm -rf "$backup_dir"

                success "Basic backup created: ${backup_name}.tar.gz"
            fi
            ;;

        restore)
            local backup_file="${2:-}"
            if [[ -z "$backup_file" ]]; then
                error "Backup file required"
                echo "Usage: $(basename "$0") backup restore <backup-file>"
                exit 1
            fi

            header "📥 Restoring Configuration"

            if [[ -f "$SCRIPT_DIR/backup-config.sh" ]]; then
                "$SCRIPT_DIR/backup-config.sh" restore "$backup_file"
            else
                error "Backup script not found - manual restore required"
            fi
            ;;

        list|ls)
            header "📄 Available Backups"

            if [[ -f "$SCRIPT_DIR/backup-config.sh" ]]; then
                "$SCRIPT_DIR/backup-config.sh" list
            else
                warning "Backup script not found"
                info "Looking for backup files in current directory..."
                ls -la pi-gateway-backup-*.tar.gz 2>/dev/null || info "No backup files found"
            fi
            ;;

        --help)
            echo "Backup Management Commands:"
            echo
            echo "  create          Create new configuration backup"
            echo "  restore <file>  Restore from backup file"
            echo "  list            List available backups"
            echo
            ;;

        *)
            error "Unknown backup command: $action"
            echo "Available commands: create, restore, list"
            echo "Use '$(basename "$0") backup --help' for details"
            exit 1
            ;;
    esac
}

# Log viewing
cmd_logs() {
    local service="${1:-}"

    case $service in
        ssh)
            header "🔐 SSH Access Logs"
            echo -e "${BLUE}Recent SSH connections:${NC}"
            sudo grep "Accepted\|Failed" /var/log/auth.log | tail -20
            echo
            echo -e "${BLUE}Current SSH sessions:${NC}"
            who
            ;;

        vpn|wireguard)
            header "🔒 VPN Service Logs"
            sudo journalctl -u wg-quick@wg0 --no-pager -n 20
            ;;

        firewall|ufw)
            header "🔥 Firewall Logs"
            if [[ -f /var/log/ufw.log ]]; then
                sudo tail -20 /var/log/ufw.log
            else
                sudo journalctl -u ufw --no-pager -n 20
            fi
            ;;

        fail2ban)
            header "🛡️  Intrusion Detection Logs"
            if [[ -f /var/log/fail2ban.log ]]; then
                sudo tail -20 /var/log/fail2ban.log
            else
                sudo journalctl -u fail2ban --no-pager -n 20
            fi
            ;;

        system)
            header "⚙️  System Logs"
            sudo journalctl --no-pager -n 30
            ;;

        errors)
            header "❌ System Errors"
            sudo journalctl -p err --no-pager -n 20
            ;;

        --help)
            echo "Log Viewing Commands:"
            echo
            echo "  ssh             SSH access and authentication logs"
            echo "  vpn             VPN service logs"
            echo "  firewall        Firewall activity logs"
            echo "  fail2ban        Intrusion detection logs"
            echo "  system          General system logs"
            echo "  errors          System error logs only"
            echo
            ;;

        "")
            header "📄 Recent System Activity"
            echo -e "${BLUE}System errors (last 10):${NC}"
            sudo journalctl -p err --no-pager -n 10
            echo
            echo -e "${BLUE}SSH activity (last 10):${NC}"
            sudo grep "Accepted\|Failed" /var/log/auth.log | tail -10
            echo
            echo -e "${BLUE}Service status:${NC}"
            sudo systemctl --failed --no-pager
            ;;

        *)
            error "Unknown log type: $service"
            echo "Available logs: ssh, vpn, firewall, fail2ban, system, errors"
            echo "Use '$(basename "$0") logs --help' for details"
            exit 1
            ;;
    esac
}

# Security monitoring
cmd_security() {
    local action="${1:-}"

    case $action in
        status)
            header "🛡️  Security Status Overview"

            echo -e "${BLUE}Firewall Status:${NC}"
            if command -v ufw >/dev/null 2>&1; then
                sudo ufw status
            else
                warning "UFW not installed"
            fi
            echo

            echo -e "${BLUE}Intrusion Detection:${NC}"
            if command -v fail2ban-client >/dev/null 2>&1; then
                sudo fail2ban-client status
            else
                warning "Fail2ban not installed"
            fi
            echo

            echo -e "${BLUE}SSH Configuration:${NC}"
            if sudo grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
                success "Password authentication: Disabled"
            else
                warning "Password authentication: Enabled"
            fi

            if sudo grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
                success "Root login: Disabled"
            else
                warning "Root login: May be enabled"
            fi
            ;;

        scan)
            header "🔍 Security Scan"

            echo -e "${BLUE}Open ports:${NC}"
            sudo ss -tulpn | grep LISTEN
            echo

            echo -e "${BLUE}Recent failed logins:${NC}"
            sudo grep "Failed password" /var/log/auth.log | tail -10
            echo

            echo -e "${BLUE}Active network connections:${NC}"
            sudo ss -tupn | grep ESTAB | head -10
            ;;

        --help)
            echo "Security Management Commands:"
            echo
            echo "  status          Show security service status"
            echo "  scan            Perform basic security scan"
            echo
            ;;

        *)
            error "Unknown security command: $action"
            echo "Available commands: status, scan"
            echo "Use '$(basename "$0") security --help' for details"
            exit 1
            ;;
    esac
}

# Update system
cmd_update() {
    header "📦 System Update"

    echo -e "${BLUE}Updating package lists...${NC}"
    sudo apt update
    echo

    echo -e "${BLUE}Available upgrades:${NC}"
    apt list --upgradable 2>/dev/null | head -20
    echo

    read -r -p "$(echo -e "${YELLOW}Proceed with system upgrade? [y/N]: ${NC}")" confirm
    if [[ $confirm =~ ^[Yy] ]]; then
        echo -e "${BLUE}Upgrading system...${NC}"
        sudo apt upgrade -y
        echo

        echo -e "${BLUE}Cleaning up...${NC}"
        sudo apt autoremove -y
        sudo apt autoclean

        success "System update completed"

        # Check if reboot is required
        if [[ -f /var/run/reboot-required ]]; then
            warning "System reboot required for some updates"
            info "Run 'sudo reboot' when convenient"
        fi
    else
        info "Update cancelled"
    fi
}

# Setup command
cmd_setup() {
    header "⚙️  Pi Gateway Setup"

    if [[ -f "$PROJECT_ROOT/setup.sh" ]]; then
        cd "$PROJECT_ROOT"
        ./setup.sh "$@"
    else
        error "Setup script not found"
        info "Please run from Pi Gateway directory"
        exit 1
    fi
}

# Interactive menu
show_menu() {
    print_header

    echo -e "${CYAN}📋 Quick Actions Menu${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} System Status"
    echo -e "  ${YELLOW}2.${NC} VPN Management"
    echo -e "  ${YELLOW}3.${NC} View Logs"
    echo -e "  ${YELLOW}4.${NC} Security Check"
    echo -e "  ${YELLOW}5.${NC} Create Backup"
    echo -e "  ${YELLOW}6.${NC} System Update"
    echo -e "  ${YELLOW}7.${NC} Help"
    echo -e "  ${YELLOW}0.${NC} Exit"
    echo

    read -r -p "$(echo -e "${BLUE}Select option [0-7]: ${NC}")" choice

    case $choice in
        1) cmd_status ;;
        2)
            echo
            echo "VPN Commands: add <name>, remove <name>, list, status"
            read -r -p "$(echo -e "${BLUE}Enter VPN command: ${NC}")" vpn_cmd
            cmd_vpn "$vpn_cmd"
            ;;
        3)
            echo
            echo "Log types: ssh, vpn, firewall, fail2ban, system, errors"
            read -r -p "$(echo -e "${BLUE}Enter log type (or press Enter for overview): ${NC}")" log_type
            cmd_logs "$log_type"
            ;;
        4) cmd_security status ;;
        5) cmd_backup create ;;
        6) cmd_update ;;
        7) show_help ;;
        0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) error "Invalid option: $choice" ;;
    esac

    echo
    read -r -p "$(echo -e "${CYAN}Press Enter to continue...${NC}")"
    show_menu
}

# Main execution
main() {
    local command="${1:-}"

    case $command in
        status)
            cmd_status
            ;;
        setup)
            shift
            cmd_setup "$@"
            ;;
        vpn)
            shift
            cmd_vpn "$@"
            ;;
        backup)
            shift
            cmd_backup "$@"
            ;;
        logs)
            shift
            cmd_logs "$@"
            ;;
        security)
            shift
            cmd_security "$@"
            ;;
        update)
            cmd_update
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            show_menu
            ;;
        *)
            error "Unknown command: $command"
            echo "Use '$(basename "$0") help' for available commands"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
