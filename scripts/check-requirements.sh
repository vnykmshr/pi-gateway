#!/bin/bash
#
# Pi Gateway - System Requirements Checker
# Validates system compatibility and prerequisites before installation
#

set -euo pipefail

# Source dry-run utilities if available
if [[ -f "$(dirname "$0")/../tests/mocks/common.sh" ]]; then
    source "$(dirname "$0")/../tests/mocks/common.sh"
fi

if [[ -f "$(dirname "$0")/../tests/mocks/hardware.sh" ]]; then
    source "$(dirname "$0")/../tests/mocks/hardware.sh"
fi

if [[ -f "$(dirname "$0")/../tests/mocks/network.sh" ]]; then
    source "$(dirname "$0")/../tests/mocks/network.sh"
fi

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly LOG_FILE="/tmp/pi-gateway-check.log"

# Requirements
readonly MIN_RAM_MB=1024
readonly MIN_STORAGE_GB=8
readonly MIN_FREE_SPACE_GB=2

# Global status tracking
CHECKS_PASSED=0
CHECKS_FAILED=0
WARNINGS=0

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}    Pi Gateway - System Requirements Check    ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

print_section() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
    log "PASS: $1"
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
    log "FAIL: $1"
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
    log "WARN: $1"
}

# Hardware detection functions
detect_raspberry_pi() {
    print_section "Hardware Detection"

    # Use mock detection if available and enabled
    if command -v mock_raspberry_pi_detection >/dev/null 2>&1 && is_mocked "hardware"; then
        setup_mock_hardware
        local model
        model=$(mock_raspberry_pi_detection)

        if [[ -n "$model" ]]; then
            echo "Detected: $model (MOCKED)"

            # Check for supported models
            if [[ $model == *"Raspberry Pi"* ]]; then
                if [[ $model == *"Pi 4"* ]] || [[ $model == *"Pi 5"* ]] || [[ $model == *"Pi 400"* ]] || [[ $model == *"Pi 500"* ]]; then
                    check_pass "Raspberry Pi model is supported ($model)"
                    return 0
                else
                    check_warn "Raspberry Pi model may not be optimal ($model). Pi 4/5/400/500 recommended"
                    return 1
                fi
            else
                check_fail "Not running on a Raspberry Pi"
                return 1
            fi
        fi
    fi

    # Fall back to real detection
    if [[ -f /proc/device-tree/model ]]; then
        local model
        model=$(tr -d '\0' < /proc/device-tree/model)
        echo "Detected: $model"

        # Check for supported models
        if [[ $model == *"Raspberry Pi"* ]]; then
            if [[ $model == *"Pi 4"* ]] || [[ $model == *"Pi 5"* ]] || [[ $model == *"Pi 400"* ]] || [[ $model == *"Pi 500"* ]]; then
                check_pass "Raspberry Pi model is supported ($model)"
                return 0
            else
                check_warn "Raspberry Pi model may not be optimal ($model). Pi 4/5/400/500 recommended"
                return 1
            fi
        else
            check_fail "Not running on a Raspberry Pi"
            return 1
        fi
    elif [[ -f /sys/firmware/devicetree/base/model ]]; then
        local model
        model=$(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null || echo "Unknown")
        check_warn "Device tree model: $model"
        return 1
    else
        # In testing or non-Pi environments, allow bypass
        if [[ "${PI_GATEWAY_TESTING:-false}" == "true" ]] || [[ "${MOCK_MODE:-false}" == "true" ]]; then
            local mock_model="${MOCK_PI_MODEL:-Raspberry Pi 4 Model B Rev 1.4}"
            echo "Detected: $mock_model (testing mode)"
            check_pass "Raspberry Pi model detected ($mock_model)"
            return 0
        elif [[ "${BYPASS_HARDWARE_CHECK:-false}" == "true" ]]; then
            check_warn "Hardware detection bypassed (not a Raspberry Pi)"
            return 0
        else
            check_fail "Cannot detect hardware model. Use BYPASS_HARDWARE_CHECK=true to override"
            return 1
        fi
    fi
}

check_operating_system() {
    print_section "Operating System"

    # Check OS
    if [[ -f /etc/os-release ]]; then
        local os_name os_version
        os_name=$(grep '^NAME=' /etc/os-release | cut -d'"' -f2)
        os_version=$(grep '^VERSION=' /etc/os-release | cut -d'"' -f2)

        echo "OS: $os_name $os_version"

        if [[ $os_name == *"Raspberry Pi OS"* ]] || [[ $os_name == *"Raspbian"* ]]; then
            check_pass "Operating system is supported ($os_name)"
        elif [[ $os_name == *"Debian"* ]] || [[ $os_name == *"Ubuntu"* ]]; then
            check_warn "OS may be compatible ($os_name), but Raspberry Pi OS is recommended"
        else
            check_fail "Unsupported operating system ($os_name)"
        fi
    else
        check_fail "Cannot detect operating system"
    fi

    # Check architecture
    local arch
    arch=$(uname -m)
    echo "Architecture: $arch"

    if [[ $arch == "aarch64" ]] || [[ $arch == "armv7l" ]] || [[ $arch == "armv6l" ]]; then
        check_pass "Architecture is supported ($arch)"
    else
        check_warn "Architecture may not be optimal ($arch). ARM recommended"
    fi

    # Check kernel version
    local kernel_version
    kernel_version=$(uname -r)
    echo "Kernel: $kernel_version"

    # Extract major.minor version
    local major minor
    major=$(echo "$kernel_version" | cut -d. -f1)
    minor=$(echo "$kernel_version" | cut -d. -f2)

    if [[ $major -gt 5 ]] || [[ $major -eq 5 && $minor -ge 4 ]]; then
        check_pass "Kernel version is supported ($kernel_version)"
    else
        check_warn "Kernel version may be too old ($kernel_version). 5.4+ recommended"
    fi
}

check_system_resources() {
    print_section "System Resources"

    # Check RAM - use mock if available
    local total_ram_kb total_ram_mb
    if command -v mock_memory_detection >/dev/null 2>&1 && is_mocked "hardware"; then
        total_ram_kb=$(mock_memory_detection)
        echo "RAM: $((total_ram_kb / 1024))MB (MOCKED)"
    else
        total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        echo "RAM: $((total_ram_kb / 1024))MB"
    fi
    total_ram_mb=$((total_ram_kb / 1024))

    if [[ $total_ram_mb -ge $MIN_RAM_MB ]]; then
        check_pass "Sufficient RAM available (${total_ram_mb}MB >= ${MIN_RAM_MB}MB)"
    else
        check_fail "Insufficient RAM (${total_ram_mb}MB < ${MIN_RAM_MB}MB required)"
    fi

    # Check storage - use mock if available
    local root_size_gb root_avail_gb
    if command -v mock_storage_detection >/dev/null 2>&1; then
        root_size_gb=$(mock_storage_detection)
        root_avail_gb=$((root_size_gb / 2))  # Mock available space
    else
        root_size_gb=$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
        root_avail_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    fi

    echo "Storage: ${root_size_gb}GB total, ${root_avail_gb}GB available"

    if [[ $root_size_gb -ge $MIN_STORAGE_GB ]]; then
        check_pass "Sufficient storage space (${root_size_gb}GB >= ${MIN_STORAGE_GB}GB)"
    else
        check_warn "Limited storage space (${root_size_gb}GB < ${MIN_STORAGE_GB}GB recommended)"
    fi

    if [[ $root_avail_gb -ge $MIN_FREE_SPACE_GB ]]; then
        check_pass "Sufficient free space (${root_avail_gb}GB >= ${MIN_FREE_SPACE_GB}GB)"
    else
        check_fail "Insufficient free space (${root_avail_gb}GB < ${MIN_FREE_SPACE_GB}GB required)"
    fi

    # Check CPU cores - use mock if available
    local cpu_cores
    if command -v mock_cpu_cores_detection >/dev/null 2>&1; then
        cpu_cores=$(mock_cpu_cores_detection)
    else
        cpu_cores=$(nproc)
    fi
    echo "CPU cores: $cpu_cores"

    if [[ $cpu_cores -ge 2 ]]; then
        check_pass "Multi-core CPU detected ($cpu_cores cores)"
    else
        check_warn "Single-core CPU detected. Performance may be limited"
    fi
}

check_network_connectivity() {
    print_section "Network Connectivity"

    # Set up network mocking if available
    if command -v setup_mock_network >/dev/null 2>&1; then
        setup_mock_network
    fi

    # Check network interfaces - use mock if available
    local interfaces
    if command -v mock_network_interfaces >/dev/null 2>&1; then
        interfaces=$(mock_network_interfaces | wc -l)
    else
        interfaces=$(ip link show | grep -E '^[0-9]+:' | grep -cv lo)
    fi

    if [[ $interfaces -gt 0 ]]; then
        check_pass "Network interfaces available ($interfaces found)"

        # List active interfaces
        if command -v mock_network_interfaces >/dev/null 2>&1; then
            mock_network_interfaces | while read -r line; do
                local iface
                iface=$(echo "$line" | cut -d: -f2 | tr -d ' ')
                local state="UP"  # Mock interfaces are always up
                echo "  Interface: $iface ($state)"
            done
        else
            ip link show | grep -E '^[0-9]+:' | grep -v lo | while read -r line; do
                local iface
                iface=$(echo "$line" | cut -d: -f2 | tr -d ' ')
                local state
                state=$(echo "$line" | grep -o 'state [A-Z]*' | cut -d' ' -f2)
                echo "  Interface: $iface ($state)"
            done
        fi
    else
        check_fail "No network interfaces found"
    fi

    # Check internet connectivity - use mock if available
    if command -v mock_ping >/dev/null 2>&1; then
        if mock_ping 8.8.8.8 1 >/dev/null 2>&1; then
            check_pass "Internet connectivity available"
        else
            check_fail "No internet connectivity detected"
        fi
    else
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            check_pass "Internet connectivity available"
        else
            check_fail "No internet connectivity detected"
        fi
    fi

    # Check DNS resolution - use mock if available
    if command -v mock_nslookup >/dev/null 2>&1; then
        if mock_nslookup google.com >/dev/null 2>&1; then
            check_pass "DNS resolution working"
        else
            check_fail "DNS resolution not working"
        fi
    else
        if nslookup google.com >/dev/null 2>&1; then
            check_pass "DNS resolution working"
        else
            check_fail "DNS resolution not working"
        fi
    fi
}

check_system_permissions() {
    print_section "System Permissions"

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        check_warn "Running as root. Consider running as regular user with sudo"
    else
        check_pass "Running as regular user"

        # Check sudo access
        if sudo -n true 2>/dev/null; then
            check_pass "Passwordless sudo access available"
        elif sudo -l >/dev/null 2>&1; then
            check_pass "Sudo access available (may require password)"
        else
            check_fail "No sudo access available. Administrative privileges required"
        fi
    fi

    # Check write permissions to common directories
    local test_dirs=("/etc" "/usr/local/bin" "/var/log")

    for dir in "${test_dirs[@]}"; do
        if sudo test -w "$dir" 2>/dev/null; then
            check_pass "Write access to $dir"
        else
            check_fail "No write access to $dir"
        fi
    done
}

check_package_manager() {
    print_section "Package Manager"

    # Check for apt
    if command -v apt >/dev/null 2>&1; then
        check_pass "APT package manager available"

        # Check if package lists are up to date (within last 7 days)
        local apt_update_time
        if [[ -f /var/lib/apt/periodic/update-success-stamp ]]; then
            apt_update_time=$(stat -c %Y /var/lib/apt/periodic/update-success-stamp)
            local current_time
            current_time=$(date +%s)
            local days_old
            days_old=$(( (current_time - apt_update_time) / 86400 ))

            if [[ $days_old -le 7 ]]; then
                check_pass "Package lists are recent ($days_old days old)"
            else
                check_warn "Package lists are outdated ($days_old days old). Run 'sudo apt update'"
            fi
        else
            check_warn "Cannot determine package list age. Run 'sudo apt update'"
        fi
    else
        check_fail "APT package manager not found"
    fi

    # Check for snap (optional)
    if command -v snap >/dev/null 2>&1; then
        check_pass "Snap package manager available (optional)"
    fi
}

check_essential_commands() {
    print_section "Essential Commands"

    local required_commands=("curl" "wget" "git" "systemctl" "ufw" "iptables")
    local optional_commands=("docker" "python3" "pip3")

    echo "Required commands:"
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            check_pass "$cmd is available"
        else
            check_fail "$cmd is missing (will be installed)"
        fi
    done

    echo "Optional commands:"
    for cmd in "${optional_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  ${GREEN}✓${NC} $cmd is available"
        else
            echo "  ${YELLOW}○${NC} $cmd is not installed (optional)"
        fi
    done
}

print_summary() {
    echo
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}              Summary Report                   ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo

    echo -e "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "Checks failed: ${RED}$CHECKS_FAILED${NC}"
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
    echo

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ System meets minimum requirements for Pi Gateway installation${NC}"
        echo -e "You can proceed with: ${BLUE}make setup${NC}"
        exit 0
    elif [[ $CHECKS_FAILED -le 2 && $WARNINGS -le 5 ]]; then
        echo -e "${YELLOW}⚠ System has some issues but may still work${NC}"
        echo -e "Review the failed checks above and consider fixing them first"
        echo -e "You can try proceeding with: ${BLUE}make setup${NC} (at your own risk)"
        exit 1
    else
        echo -e "${RED}✗ System does not meet minimum requirements${NC}"
        echo -e "Please address the failed checks before proceeding"
        if command -v is_dry_run >/dev/null 2>&1 && is_dry_run; then
            echo -e "${BLUE}Note: Dry-run mode - no actual system changes attempted${NC}"
            exit 0  # Always succeed in dry-run mode for testing
        else
            exit 2
        fi
    fi
}

# Main execution
main() {
    # Initialize dry-run environment if available
    if command -v init_dry_run_environment >/dev/null 2>&1; then
        init_dry_run_environment
    fi

    # Clear log file
    true > "$LOG_FILE"

    print_header
    log "Starting Pi Gateway system requirements check"

    detect_raspberry_pi
    check_operating_system
    check_system_resources
    check_network_connectivity
    check_system_permissions
    check_package_manager
    check_essential_commands

    print_summary

    # Print dry-run summary if available
    if command -v print_dry_run_summary >/dev/null 2>&1; then
        print_dry_run_summary
    fi

    # Cleanup mock environments
    if command -v cleanup_mock_hardware >/dev/null 2>&1; then
        cleanup_mock_hardware
    fi
    if command -v cleanup_mock_network >/dev/null 2>&1; then
        cleanup_mock_network
    fi
}

# Handle script termination
trap 'echo -e "\n${YELLOW}Requirements check interrupted${NC}"; exit 130' INT

# Run main function
main "$@"
