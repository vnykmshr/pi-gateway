#!/bin/bash
#
# Pi Gateway Pre-Flight Check
# Validates all prerequisites before setup begins
#

set -euo pipefail

# Source common utilities
source "$(dirname "$0")/common.sh"

# Configuration
readonly MIN_DISK_GB=8
readonly REQUIRED_COMMANDS=("curl" "wget" "systemctl" "iptables")

# Counters
CHECK_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
WARNING_COUNT=0

# Check functions
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
    echo -e "${BLUE}║               ${WHITE}Pi Gateway Pre-Flight Check${NC}${BLUE}               ║${NC}"
    echo -e "${BLUE}║     ${CYAN}Validating system requirements before setup${NC}${BLUE}      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# System checks
check_operating_system() {
    check_start "Operating system compatibility"
    if check_os 2>/dev/null; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "$ID" == "raspbian" ]] || [[ "$ID_LIKE" == *"debian"* ]]; then
            check_pass "Running compatible OS: $PRETTY_NAME"
        else
            check_warning "Untested OS: $PRETTY_NAME"
        fi
    else
        check_fail "Cannot determine operating system"
        return 1
    fi
}

check_memory_requirements() {
    check_start "Memory requirements (minimum ${MIN_RAM_MB}MB)"
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_mb=$((total_mem_kb / 1024))

    if [[ $total_mem_mb -ge $MIN_RAM_MB ]]; then
        check_pass "Available: ${total_mem_mb}MB"
    else
        check_fail "Insufficient RAM: ${total_mem_mb}MB (need ${MIN_RAM_MB}MB+)"
        return 1
    fi
}

check_disk_space() {
    check_start "Disk space requirements (minimum ${MIN_DISK_GB}GB)"
    local available_kb
    available_kb=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_kb / 1024 / 1024))

    if [[ $available_gb -ge $MIN_DISK_GB ]]; then
        check_pass "Available: ${available_gb}GB"
    else
        check_fail "Insufficient disk space: ${available_gb}GB (need ${MIN_DISK_GB}GB+)"
        return 1
    fi
}

check_internet_connectivity() {
    check_start "Internet connectivity"
    if check_internet; then
        check_pass "Internet connection verified"
    else
        check_fail "No internet connectivity detected"
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
            check_fail "Missing: $cmd"
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        echo
        error "Missing required commands: ${missing_commands[*]}"
        info "Install with: sudo apt update && sudo apt install -y ${missing_commands[*]}"
        return 1
    fi
}

# Results summary
show_summary() {
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                        ${WHITE}Summary${NC}${BLUE}                         ║${NC}"
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
    init_logging "pre-flight-check"
    show_header

    echo -e "${WHITE}Running system validation checks...${NC}"
    echo

    # Run all checks
    check_operating_system
    check_memory_requirements
    check_disk_space
    check_internet_connectivity
    check_required_commands

    show_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi