#!/bin/bash
#
# Pi Gateway - Common Dry-Run and Mocking Utilities
# Shared functions for testing and dry-run execution
#

# Dry-run configuration
DRY_RUN="${DRY_RUN:-false}"
MOCK_HARDWARE="${MOCK_HARDWARE:-false}"
MOCK_NETWORK="${MOCK_NETWORK:-false}"
MOCK_SYSTEM="${MOCK_SYSTEM:-false}"
VERBOSE_DRY_RUN="${VERBOSE_DRY_RUN:-false}"

# Dry-run logging
DRY_RUN_LOG="${DRY_RUN_LOG:-/tmp/pi-gateway-dry-run.log}"

# Colors for dry-run output (avoid conflicts with script colors)
DRY_RUN_COLOR='\033[0;36m'  # Cyan
MOCK_COLOR='\033[0;35m'     # Magenta

# Initialize dry-run logging
init_dry_run_log() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "=== Pi Gateway Dry-Run Session Started: $(date) ===" > "$DRY_RUN_LOG"
        echo "DRY_RUN=$DRY_RUN" >> "$DRY_RUN_LOG"
        echo "MOCK_HARDWARE=$MOCK_HARDWARE" >> "$DRY_RUN_LOG"
        echo "MOCK_NETWORK=$MOCK_NETWORK" >> "$DRY_RUN_LOG"
        echo "MOCK_SYSTEM=$MOCK_SYSTEM" >> "$DRY_RUN_LOG"
        echo "================================" >> "$DRY_RUN_LOG"
    fi
}

# Dry-run command execution wrapper
execute_command() {
    local cmd="$*"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${DRY_RUN_COLOR}[DRY-RUN]${NC} $cmd"
        echo "DRY_RUN: $cmd" >> "$DRY_RUN_LOG"

        if [[ "$VERBOSE_DRY_RUN" == "true" ]]; then
            echo "    ↳ Command would execute: $cmd"
        fi

        # Return success for most commands in dry-run
        return 0
    else
        # Execute the actual command
        eval "$cmd"
    fi
}

# Safe file operation wrapper
safe_file_operation() {
    local operation="$1"
    local file="$2"
    local content="$3"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${DRY_RUN_COLOR}[DRY-RUN]${NC} $operation $file"
        echo "DRY_RUN: $operation $file" >> "$DRY_RUN_LOG"

        if [[ "$VERBOSE_DRY_RUN" == "true" ]]; then
            case "$operation" in
                "write"|"create")
                    echo "    ↳ Would create/modify: $file"
                    if [[ -n "$content" ]]; then
                        echo "    ↳ Content preview: ${content:0:100}..."
                    fi
                    ;;
                "backup")
                    echo "    ↳ Would backup: $file"
                    ;;
                "chmod"|"chown")
                    echo "    ↳ Would change permissions: $operation $file"
                    ;;
            esac
        fi
        return 0
    else
        # Execute actual file operation
        case "$operation" in
            "write"|"create")
                if [[ -n "$content" ]]; then
                    echo "$content" > "$file"
                else
                    touch "$file"
                fi
                ;;
            "backup")
                cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
                ;;
            "chmod")
                chmod "$content" "$file"
                ;;
            "chown")
                chown "$content" "$file"
                ;;
        esac
    fi
}

# Package management wrapper
mock_package_operation() {
    local operation="$1"
    shift
    local packages=("$@")

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${DRY_RUN_COLOR}[DRY-RUN]${NC} apt $operation ${packages[*]}"
        echo "DRY_RUN: apt $operation ${packages[*]}" >> "$DRY_RUN_LOG"

        if [[ "$VERBOSE_DRY_RUN" == "true" ]]; then
            for package in "${packages[@]}"; do
                echo "    ↳ Would $operation package: $package"
            done
        fi
        return 0
    else
        apt "$operation" -y "${packages[@]}"
    fi
}

# Service management wrapper
mock_service_operation() {
    local operation="$1"
    local service="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${DRY_RUN_COLOR}[DRY-RUN]${NC} systemctl $operation $service"
        echo "DRY_RUN: systemctl $operation $service" >> "$DRY_RUN_LOG"

        if [[ "$VERBOSE_DRY_RUN" == "true" ]]; then
            echo "    ↳ Would $operation service: $service"
        fi
        return 0
    else
        systemctl "$operation" "$service"
    fi
}

# System configuration wrapper (sysctl, etc.)
mock_system_config() {
    local operation="$1"
    local parameter="$2"
    local value="$3"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${DRY_RUN_COLOR}[DRY-RUN]${NC} $operation $parameter = $value"
        echo "DRY_RUN: $operation $parameter = $value" >> "$DRY_RUN_LOG"

        if [[ "$VERBOSE_DRY_RUN" == "true" ]]; then
            echo "    ↳ Would set system parameter: $parameter = $value"
        fi
        return 0
    else
        case "$operation" in
            "sysctl")
                sysctl -w "$parameter=$value"
                ;;
            *)
                echo "Unknown system config operation: $operation"
                return 1
                ;;
        esac
    fi
}

# Print dry-run summary
print_dry_run_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo
        echo -e "${DRY_RUN_COLOR}======================================${NC}"
        echo -e "${DRY_RUN_COLOR}       DRY-RUN EXECUTION SUMMARY      ${NC}"
        echo -e "${DRY_RUN_COLOR}======================================${NC}"
        echo -e "${DRY_RUN_COLOR}Mode:${NC} Dry-run simulation"
        echo -e "${DRY_RUN_COLOR}Log:${NC} $DRY_RUN_LOG"

        if [[ -f "$DRY_RUN_LOG" ]]; then
            local command_count
            command_count=$(grep -c "^DRY_RUN:" "$DRY_RUN_LOG")
            echo -e "${DRY_RUN_COLOR}Commands simulated:${NC} $command_count"
        fi

        echo -e "${DRY_RUN_COLOR}Status:${NC} No actual system changes made"
        echo -e "${DRY_RUN_COLOR}======================================${NC}"
        echo
    fi
}

# Helper function to check if we're in dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Helper function to check if mocking is enabled
is_mocked() {
    local mock_type="$1"

    case "$mock_type" in
        "hardware"|"hw")
            [[ "$MOCK_HARDWARE" == "true" ]]
            ;;
        "network"|"net")
            [[ "$MOCK_NETWORK" == "true" ]]
            ;;
        "system"|"sys")
            [[ "$MOCK_SYSTEM" == "true" ]]
            ;;
        *)
            [[ "$DRY_RUN" == "true" ]]
            ;;
    esac
}

# Initialize dry-run environment
init_dry_run_environment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        init_dry_run_log
        echo -e "${DRY_RUN_COLOR}🧪 Pi Gateway Dry-Run Mode Enabled${NC}"
        echo -e "${DRY_RUN_COLOR}   → No actual system changes will be made${NC}"
        echo -e "${DRY_RUN_COLOR}   → All commands will be simulated${NC}"
        if [[ "$VERBOSE_DRY_RUN" == "true" ]]; then
            echo -e "${DRY_RUN_COLOR}   → Verbose output enabled${NC}"
        fi
        echo -e "${DRY_RUN_COLOR}   → Log file: $DRY_RUN_LOG${NC}"
        echo
    fi
}

# Export functions for use in other scripts
export -f execute_command
export -f safe_file_operation
export -f mock_package_operation
export -f mock_service_operation
export -f mock_system_config
export -f print_dry_run_summary
export -f is_dry_run
export -f is_mocked
export -f init_dry_run_environment
