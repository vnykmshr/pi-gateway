#!/bin/bash
#
# Pi Gateway - System Mocking Functions
# Mock system commands and operations
#

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Mock system configuration
MOCK_USER="${MOCK_USER:-pi}"
MOCK_SUDO_ACCESS="${MOCK_SUDO_ACCESS:-true}"
MOCK_SYSTEMD_ENABLED="${MOCK_SYSTEMD_ENABLED:-true}"

# Mock systemctl command
mock_systemctl() {
    local operation="$1"
    local service="$2"

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} systemctl $operation $service"

        case "$operation" in
            "enable"|"disable"|"start"|"stop"|"restart"|"reload")
                echo "Mock: $service $operation successful"
                return 0
                ;;
            "status")
                echo "● $service.service - Mock Service"
                echo "   Loaded: loaded (/lib/systemd/system/$service.service; enabled)"
                echo "   Active: active (running) since $(date)"
                echo "   Process: 12345 ExecStart=/usr/sbin/$service"
                return 0
                ;;
            "is-enabled")
                if [[ "$MOCK_SYSTEMD_ENABLED" == "true" ]]; then
                    echo "enabled"
                    return 0
                else
                    echo "disabled"
                    return 1
                fi
                ;;
            "is-active")
                echo "active"
                return 0
                ;;
            *)
                echo "Mock: Unknown systemctl operation: $operation"
                return 1
                ;;
        esac
    fi

    # Fall back to real systemctl
    systemctl "$operation" "$service"
}

# Mock apt package management
mock_apt() {
    local operation="$1"
    shift
    local packages=("$@")

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} apt $operation ${packages[*]}"

        case "$operation" in
            "update")
                echo "Hit:1 http://raspbian.raspberrypi.org/raspbian bookworm InRelease"
                echo "Hit:2 http://archive.raspberrypi.org/debian bookworm InRelease"
                echo "Reading package lists... Done"
                return 0
                ;;
            "install")
                for package in "${packages[@]}"; do
                    if [[ "$package" != "-y" ]]; then
                        echo "Reading package lists... Done"
                        echo "Building dependency tree... Done"
                        echo "The following NEW packages will be installed:"
                        echo "  $package"
                        echo "Setting up $package (mock-version) ..."
                    fi
                done
                return 0
                ;;
            "upgrade")
                echo "Reading package lists... Done"
                echo "Building dependency tree... Done"
                echo "Calculating upgrade... Done"
                echo "0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded."
                return 0
                ;;
            "remove"|"purge")
                for package in "${packages[@]}"; do
                    if [[ "$package" != "-y" ]]; then
                        echo "Reading package lists... Done"
                        echo "Building dependency tree... Done"
                        echo "The following packages will be REMOVED:"
                        echo "  $package"
                        echo "Removing $package (mock-version) ..."
                    fi
                done
                return 0
                ;;
            *)
                echo "Mock: Unknown apt operation: $operation"
                return 1
                ;;
        esac
    fi

    # Fall back to real apt
    apt "$operation" "${packages[@]}"
}

# Mock sysctl command
mock_sysctl() {
    local args=("$@")

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} sysctl ${args[*]}"

        if [[ "${args[0]}" == "-p" ]]; then
            echo "Mock: Loading sysctl settings from ${args[1]:-/etc/sysctl.conf}"
            echo "net.ipv4.ip_forward = 0"
            echo "net.ipv4.conf.all.accept_redirects = 0"
            echo "kernel.randomize_va_space = 2"
            return 0
        elif [[ "${args[0]}" == "-w" ]]; then
            echo "Mock: Setting ${args[1]}"
            return 0
        else
            # Simulate sysctl read
            case "${args[0]}" in
                "net.ipv4.ip_forward")
                    echo "net.ipv4.ip_forward = 0"
                    ;;
                "kernel.randomize_va_space")
                    echo "kernel.randomize_va_space = 2"
                    ;;
                *)
                    echo "${args[0]} = mock_value"
                    ;;
            esac
            return 0
        fi
    fi

    # Fall back to real sysctl
    sysctl "${args[@]}"
}

# Mock ufw firewall command
mock_ufw() {
    local args=("$@")

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} ufw ${args[*]}"

        case "${args[0]}" in
            "enable")
                echo "Mock: Firewall is active and enabled on system startup"
                return 0
                ;;
            "disable")
                echo "Mock: Firewall stopped and disabled on system startup"
                return 0
                ;;
            "reset")
                echo "Mock: Resetting all rules to installed defaults"
                return 0
                ;;
            "status")
                echo "Status: active"
                echo ""
                echo "To                         Action      From"
                echo "--                         ------      ----"
                echo "22/tcp                     ALLOW       Anywhere"
                echo "51820/udp                  ALLOW       Anywhere"
                return 0
                ;;
            "allow"|"deny")
                echo "Mock: Rule added (v6)"
                echo "Mock: Rule added"
                return 0
                ;;
            "default")
                echo "Mock: Default ${args[1]} policy changed to '${args[2]}'"
                return 0
                ;;
            *)
                echo "Mock: UFW command executed: ${args[*]}"
                return 0
                ;;
        esac
    fi

    # Fall back to real ufw
    ufw "${args[@]}"
}

# Mock user management commands
mock_useradd() {
    local args=("$@")

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} useradd ${args[*]}"
        echo "Mock: User account created successfully"
        return 0
    fi

    # Fall back to real useradd
    useradd "${args[@]}"
}

mock_usermod() {
    local args=("$@")

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} usermod ${args[*]}"
        echo "Mock: User account modified successfully"
        return 0
    fi

    # Fall back to real usermod
    usermod "${args[@]}"
}

mock_passwd() {
    local args=("$@")

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} passwd ${args[*]}"

        if [[ "${args[0]}" == "-l" ]]; then
            echo "Mock: User account locked"
        else
            echo "Mock: Password changed successfully"
        fi
        return 0
    fi

    # Fall back to real passwd
    passwd "${args[@]}"
}

# Mock file permission commands
mock_chmod() {
    local mode="$1"
    local file="$2"

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} chmod $mode $file"
        return 0
    fi

    # Fall back to real chmod
    chmod "$mode" "$file"
}

mock_chown() {
    local owner="$1"
    local file="$2"

    if is_mocked "system" || is_dry_run; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} chown $owner $file"
        return 0
    fi

    # Fall back to real chown
    chown "$owner" "$file"
}

# Mock process management
mock_sudo() {
    local args=("$@")

    if is_mocked "system" || is_dry_run; then
        if [[ "${args[0]}" == "-n" && "${args[1]}" == "true" ]]; then
            # Test passwordless sudo
            if [[ "$MOCK_SUDO_ACCESS" == "true" ]]; then
                echo -e "  ${MOCK_COLOR}[MOCK]${NC} Passwordless sudo access verified"
                return 0
            else
                echo -e "  ${MOCK_COLOR}[MOCK]${NC} sudo: a password is required"
                return 1
            fi
        else
            echo -e "  ${MOCK_COLOR}[MOCK]${NC} sudo ${args[*]}"
            # Execute the command without sudo in mock mode
            "${args[@]}"
            return $?
        fi
    fi

    # Fall back to real sudo
    sudo "${args[@]}"
}

# Set up mock system environment
setup_mock_system() {
    if is_mocked "system" || is_dry_run; then
        echo -e "${MOCK_COLOR}⚙️  Setting up mock system environment${NC}"
        echo -e "${MOCK_COLOR}   → User: $MOCK_USER${NC}"
        echo -e "${MOCK_COLOR}   → Sudo access: $MOCK_SUDO_ACCESS${NC}"
        echo -e "${MOCK_COLOR}   → Systemd enabled: $MOCK_SYSTEMD_ENABLED${NC}"
        echo

        # Create command aliases for mocking
        alias systemctl='mock_systemctl'
        alias apt='mock_apt'
        alias sysctl='mock_sysctl'
        alias ufw='mock_ufw'
        alias useradd='mock_useradd'
        alias usermod='mock_usermod'
        alias passwd='mock_passwd'
        alias chmod='mock_chmod'
        alias chown='mock_chown'

        return 0
    fi
}

# Cleanup mock system environment
cleanup_mock_system() {
    if is_mocked "system" || is_dry_run; then
        unalias systemctl 2>/dev/null || true
        unalias apt 2>/dev/null || true
        unalias sysctl 2>/dev/null || true
        unalias ufw 2>/dev/null || true
        unalias useradd 2>/dev/null || true
        unalias usermod 2>/dev/null || true
        unalias passwd 2>/dev/null || true
        unalias chmod 2>/dev/null || true
        unalias chown 2>/dev/null || true
    fi
}

# Validate mock system setup
validate_mock_system() {
    if ! is_mocked "system" && ! is_dry_run; then
        return 0
    fi

    echo -e "${MOCK_COLOR}🔍 Validating mock system setup${NC}"

    local validation_passed=true

    # Test systemctl
    if mock_systemctl status ssh >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Mock systemctl working"
    else
        echo -e "  ${RED}✗${NC} Mock systemctl failed"
        validation_passed=false
    fi

    # Test apt
    if mock_apt update >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Mock apt working"
    else
        echo -e "  ${RED}✗${NC} Mock apt failed"
        validation_passed=false
    fi

    # Test sysctl
    if mock_sysctl net.ipv4.ip_forward >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Mock sysctl working"
    else
        echo -e "  ${RED}✗${NC} Mock sysctl failed"
        validation_passed=false
    fi

    if [[ "$validation_passed" == "true" ]]; then
        echo -e "${MOCK_COLOR}✅ Mock system validation passed${NC}"
        return 0
    else
        echo -e "${MOCK_COLOR}❌ Mock system validation failed${NC}"
        return 1
    fi
}

# Export mock functions
export -f mock_systemctl
export -f mock_apt
export -f mock_sysctl
export -f mock_ufw
export -f mock_useradd
export -f mock_usermod
export -f mock_passwd
export -f mock_chmod
export -f mock_chown
export -f mock_sudo
export -f setup_mock_system
export -f cleanup_mock_system
export -f validate_mock_system
