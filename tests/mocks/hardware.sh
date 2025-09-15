#!/bin/bash
#
# Pi Gateway - Hardware Mocking Functions
# Mock hardware detection and system information
#

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Mock hardware configuration
MOCK_PI_MODEL="${MOCK_PI_MODEL:-Raspberry Pi 4 Model B Rev 1.4}"
MOCK_PI_MEMORY_MB="${MOCK_PI_MEMORY_MB:-4096}"
MOCK_PI_STORAGE_GB="${MOCK_PI_STORAGE_GB:-32}"
MOCK_PI_ARCHITECTURE="${MOCK_PI_ARCHITECTURE:-aarch64}"
MOCK_PI_CPU_CORES="${MOCK_PI_CPU_CORES:-4}"

# Mock hardware detection functions
mock_raspberry_pi_detection() {
    if is_mocked "hardware"; then
        echo "$MOCK_PI_MODEL"
        return 0
    fi

    # Fall back to real detection
    if [[ -f /proc/device-tree/model ]]; then
        tr -d '\0' < /proc/device-tree/model
    else
        return 1
    fi
}

# Mock system memory detection
mock_memory_detection() {
    if is_mocked "hardware"; then
        echo "$(( MOCK_PI_MEMORY_MB * 1024 ))"
        return 0
    fi

    # Fall back to real detection
    if [[ -f /proc/meminfo ]]; then
        grep MemTotal /proc/meminfo | awk '{print $2}'
    else
        return 1
    fi
}

# Mock storage detection
mock_storage_detection() {
    if is_mocked "hardware"; then
        echo "${MOCK_PI_STORAGE_GB}"
        return 0
    fi

    # Fall back to real detection
    df -BG / | awk 'NR==2 {print $2}' | sed 's/G//'
}

# Mock CPU architecture detection
mock_architecture_detection() {
    if is_mocked "hardware"; then
        echo "$MOCK_PI_ARCHITECTURE"
        return 0
    fi

    # Fall back to real detection
    uname -m
}

# Mock CPU cores detection
mock_cpu_cores_detection() {
    if is_mocked "hardware"; then
        echo "$MOCK_PI_CPU_CORES"
        return 0
    fi

    # Fall back to real detection
    nproc
}

# Mock OS detection
mock_os_detection() {
    if is_mocked "hardware"; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} OS: Raspberry Pi OS (simulated)"

        # Create mock os-release
        cat > /tmp/mock-os-release << 'EOF'
PRETTY_NAME="Raspberry Pi OS (64-bit)"
NAME="Raspberry Pi OS"
VERSION_ID="12"
VERSION="12 (bookworm)"
VERSION_CODENAME=bookworm
ID=debian
ID_LIKE=debian
HOME_URL="http://www.raspberrypi.org/"
SUPPORT_URL="http://www.raspberrypi.org/forums/"
BUG_REPORT_URL="http://www.raspberrypi.org/forums/"
EOF
        return 0
    fi

    # Use real os-release if available
    return 0
}

# Mock kernel version detection
mock_kernel_detection() {
    if is_mocked "hardware"; then
        local mock_kernel="6.1.21-v8+"
        echo "$mock_kernel"
        return 0
    fi

    # Fall back to real detection
    uname -r
}

# Set up mock hardware environment
setup_mock_hardware() {
    if is_mocked "hardware"; then
        echo -e "${MOCK_COLOR}🔧 Setting up mock Pi hardware environment${NC}"
        echo -e "${MOCK_COLOR}   → Model: $MOCK_PI_MODEL${NC}"
        echo -e "${MOCK_COLOR}   → Memory: ${MOCK_PI_MEMORY_MB}MB${NC}"
        echo -e "${MOCK_COLOR}   → Storage: ${MOCK_PI_STORAGE_GB}GB${NC}"
        echo -e "${MOCK_COLOR}   → Architecture: $MOCK_PI_ARCHITECTURE${NC}"
        echo -e "${MOCK_COLOR}   → CPU cores: $MOCK_PI_CPU_CORES${NC}"
        echo

        # Set up mock files
        mock_raspberry_pi_detection > /dev/null
        mock_memory_detection > /dev/null
        mock_os_detection > /dev/null

        return 0
    fi
}

# Cleanup mock hardware environment
cleanup_mock_hardware() {
    if is_mocked "hardware"; then
        rm -f /tmp/mock-pi-model
        rm -f /tmp/mock-meminfo
        rm -f /tmp/mock-os-release
    fi
}

# Mock hardware validation
validate_mock_hardware() {
    if ! is_mocked "hardware"; then
        return 0
    fi

    echo -e "${MOCK_COLOR}🔍 Validating mock hardware setup${NC}"

    local validation_passed=true

    # Check mock model
    if ! mock_raspberry_pi_detection >/dev/null; then
        echo -e "  ${RED}✗${NC} Mock Pi model detection failed"
        validation_passed=false
    else
        echo -e "  ${GREEN}✓${NC} Mock Pi model: $(mock_raspberry_pi_detection)"
    fi

    # Check mock memory
    local mem_kb
    mem_kb=$(mock_memory_detection)
    if [[ -z "$mem_kb" ]]; then
        echo -e "  ${RED}✗${NC} Mock memory detection failed"
        validation_passed=false
    else
        echo -e "  ${GREEN}✓${NC} Mock memory: $((mem_kb / 1024))MB"
    fi

    # Check mock architecture
    local arch
    arch=$(mock_architecture_detection)
    if [[ -z "$arch" ]]; then
        echo -e "  ${RED}✗${NC} Mock architecture detection failed"
        validation_passed=false
    else
        echo -e "  ${GREEN}✓${NC} Mock architecture: $arch"
    fi

    if [[ "$validation_passed" == "true" ]]; then
        echo -e "${MOCK_COLOR}✅ Mock hardware validation passed${NC}"
        return 0
    else
        echo -e "${MOCK_COLOR}❌ Mock hardware validation failed${NC}"
        return 1
    fi
}

# Export mock functions
export -f mock_raspberry_pi_detection
export -f mock_memory_detection
export -f mock_storage_detection
export -f mock_architecture_detection
export -f mock_cpu_cores_detection
export -f mock_os_detection
export -f mock_kernel_detection
export -f setup_mock_hardware
export -f cleanup_mock_hardware
export -f validate_mock_hardware
