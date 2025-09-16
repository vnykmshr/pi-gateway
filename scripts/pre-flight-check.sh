#!/bin/bash
#
# Pi Gateway Pre-Flight Check
# Validates all prerequisites before setup begins
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
readonly MIN_RAM_MB=1024
readonly MIN_DISK_GB=8
readonly REQUIRED_COMMANDS=("curl" "wget" "systemctl" "iptables")

# Counters
CHECK_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
WARNING_COUNT=0

# Logging functions
check_start() {
    ((CHECK_COUNT++))
    echo -n "  ${CYAN}[$CHECK_COUNT]${NC} $1... "
}

check_pass() {
    ((PASS_COUNT++))
    echo -e "${GREEN}✅ PASS${NC}"
    [[ -n "${1:-}" ]] && echo -e "      ${WHITE}→${NC} $1"
}

check_fail() {
    ((FAIL_COUNT++))
    echo -e "${RED}❌ FAIL${NC}"
    [[ -n "${1:-}" ]] && echo -e "      ${WHITE}→${NC} $1"
}

check_warning() {
    ((WARNING_COUNT++))
    echo -e "${YELLOW}⚠️  WARN${NC}"
    [[ -n "${1:-}" ]] && echo -e "      ${WHITE}→${NC} $1"
}

# Header
show_header() {
    clear
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║               ${WHITE}Pi Gateway Pre-Flight Check${NC}${BLUE}               ║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║     ${CYAN}Validating system requirements before setup${NC}${BLUE}      ║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${WHITE}This check validates your system before Pi Gateway installation.${NC}"
    echo -e "${WHITE}All critical requirements must pass before proceeding.${NC}"
    echo
}

# System checks
check_operating_system() {
    check_start "Operating system compatibility"

    if [[ ! -f /etc/os-release ]]; then
        check_fail "Cannot determine operating system"
        return 1
    fi

    source /etc/os-release

    if [[ "$ID" == "raspbian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
        check_pass "Running compatible OS: $PRETTY_NAME"
    else
        check_warning "Untested OS: $PRETTY_NAME (may work but not officially supported)"
    fi
}

check_hardware_platform() {
    check_start "Hardware platform detection"

    local hardware="Unknown"
    if [[ -f /proc/cpuinfo ]]; then
        if grep -q "Raspberry Pi" /proc/cpuinfo; then
            hardware=$(grep "Model" /proc/cpuinfo | cut -d: -f2 | xargs)
            check_pass "Detected: $hardware"
        else
            local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
            check_warning "Non-Pi hardware detected: $cpu_model"
        fi
    else
        check_warning "Cannot detect hardware platform"
    fi
}

check_memory_requirements() {
    check_start "Memory requirements (minimum ${MIN_RAM_MB}MB)"

    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))

    if [[ $total_mem_mb -ge $MIN_RAM_MB ]]; then
        check_pass "Available: ${total_mem_mb}MB"
    else
        check_fail "Insufficient RAM: ${total_mem_mb}MB (need minimum ${MIN_RAM_MB}MB)"
        return 1
    fi
}

check_disk_space() {
    check_start "Disk space requirements (minimum ${MIN_DISK_GB}GB)"

    local available_kb=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_kb / 1024 / 1024))

    if [[ $available_gb -ge $MIN_DISK_GB ]]; then
        check_pass "Available: ${available_gb}GB"
    else
        check_fail "Insufficient disk space: ${available_gb}GB (need minimum ${MIN_DISK_GB}GB)"
        return 1
    fi
}

check_internet_connectivity() {
    check_start "Internet connectivity"

    # Test multiple endpoints for reliability
    local test_hosts=("8.8.8.8" "1.1.1.1" "github.com")
    local success=0

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            ((success++))
            break
        fi
    done

    if [[ $success -gt 0 ]]; then
        check_pass "Internet connection verified"
    else
        check_fail "No internet connectivity detected"
        return 1
    fi
}

check_dns_resolution() {
    check_start "DNS resolution"

    if nslookup github.com >/dev/null 2>&1; then
        check_pass "DNS resolution working"
    else
        check_fail "DNS resolution not working"
        return 1
    fi
}

check_sudo_access() {
    check_start "Sudo privileges"

    if sudo -n true 2>/dev/null; then
        check_pass "Passwordless sudo configured"
    elif sudo -l >/dev/null 2>&1; then
        check_warning "Sudo available but may require password"
    else
        check_fail "No sudo access available"
        return 1
    fi
}

check_required_commands() {
    local missing_commands=()

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        check_start "Command availability: $cmd"

        if command -v "$cmd" >/dev/null 2>&1; then
            check_pass "Available: $(command -v "$cmd")"
        else
            check_fail "Command not found: $cmd"
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        echo
        echo -e "${RED}Missing required commands:${NC} ${missing_commands[*]}"
        echo -e "${WHITE}Install with:${NC} sudo apt update && sudo apt install -y ${missing_commands[*]}"
        return 1
    fi
}

check_ssh_service() {
    check_start "SSH service status"

    if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
        check_pass "SSH service is running"
    else
        check_warning "SSH service not running (will be enabled during setup)"
    fi
}

check_firewall_status() {
    check_start "Firewall status"

    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -1)
        if [[ "$ufw_status" == *"active"* ]]; then
            check_warning "UFW firewall is active (will be reconfigured during setup)"
        else
            check_pass "UFW available and inactive"
        fi
    else
        check_warning "UFW not installed (will be installed during setup)"
    fi
}

check_package_manager() {
    check_start "Package manager functionality"

    if apt list --installed >/dev/null 2>&1; then
        check_pass "APT package manager working"
    else
        check_fail "APT package manager not functioning"
        return 1
    fi
}

check_system_updates() {
    check_start "System update status"

    # Check if we can update package lists
    if sudo apt update >/dev/null 2>&1; then
        local updates=$(apt list --upgradable 2>/dev/null | wc -l)
        if [[ $updates -gt 1 ]]; then
            check_warning "$((updates - 1)) package updates available"
        else
            check_pass "System is up to date"
        fi
    else
        check_warning "Cannot check for system updates"
    fi
}

# Network configuration checks
check_network_configuration() {
    check_start "Network configuration"

    local ip_address=$(hostname -I | awk '{print $1}')
    local gateway=$(ip route show default | awk '/default/ {print $3; exit}')

    if [[ -n "$ip_address" && -n "$gateway" ]]; then
        check_pass "IP: $ip_address, Gateway: $gateway"
    else
        check_fail "Network configuration incomplete"
        return 1
    fi
}

# Show recommendations based on check results
show_recommendations() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║                       ${WHITE}Recommendations${NC}${BLUE}                     ║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✅ All critical checks passed!${NC}"
        echo -e "   Your system is ready for Pi Gateway installation."
        echo
        echo -e "${WHITE}Next steps:${NC}"
        echo -e "   1. Run: ${CYAN}curl -sSL https://raw.githubusercontent.com/vnykmshr/pi-gateway/main/scripts/quick-install.sh | bash${NC}"
        echo -e "   2. Or clone the repository and run: ${CYAN}make setup${NC}"
    else
        echo -e "${RED}❌ Critical issues found!${NC}"
        echo -e "   Please resolve the failed checks before proceeding."
        echo
        echo -e "${WHITE}Common solutions:${NC}"
        echo -e "   • Update system: ${CYAN}sudo apt update && sudo apt upgrade -y${NC}"
        echo -e "   • Install missing packages: ${CYAN}sudo apt install -y curl wget${NC}"
        echo -e "   • Check network connection and DNS settings"
        echo -e "   • Ensure sufficient disk space (consider expanding filesystem)"
    fi

    if [[ $WARNING_COUNT -gt 0 ]]; then
        echo
        echo -e "${YELLOW}⚠️  Warnings found:${NC}"
        echo -e "   Setup may proceed but some features might need attention."
    fi
}

# Summary
show_summary() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║                        ${WHITE}Summary${NC}${BLUE}                         ║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  ${WHITE}Total checks:${NC} $CHECK_COUNT"
    echo -e "  ${GREEN}Passed:${NC} $PASS_COUNT"
    echo -e "  ${YELLOW}Warnings:${NC} $WARNING_COUNT"
    echo -e "  ${RED}Failed:${NC} $FAIL_COUNT"
    echo

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "  ${GREEN}🎉 System ready for Pi Gateway installation!${NC}"
        return 0
    else
        echo -e "  ${RED}⛔ Please resolve issues before proceeding.${NC}"
        return 1
    fi
}

# Main execution
main() {
    show_header

    echo -e "${WHITE}Running system validation checks...${NC}"
    echo

    # Core system checks
    check_operating_system
    check_hardware_platform
    check_memory_requirements
    check_disk_space

    # Network checks
    check_internet_connectivity
    check_dns_resolution
    check_network_configuration

    # System capability checks
    check_sudo_access
    check_required_commands
    check_package_manager
    check_system_updates

    # Service checks
    check_ssh_service
    check_firewall_status

    # Show results
    show_recommendations
    show_summary
}

# Run checks if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi