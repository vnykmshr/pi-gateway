#!/bin/bash
#
# Pi Gateway - Master Setup Script
# Comprehensive homelab bootstrap system orchestration
#

# Show help function (defined early to handle help before strict mode)
show_help() {
    echo "Pi Gateway Setup - Comprehensive Homelab Bootstrap System"
    echo
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -d, --dry-run        Run in dry-run mode (no system changes)"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -n, --non-interactive  Run without interactive prompts"
    echo "  -c, --config FILE    Use specific configuration file"
    echo
    echo "Examples:"
    echo "  $(basename "$0")                    # Interactive setup"
    echo "  $(basename "$0") --dry-run          # Test without changes"
    echo "  $(basename "$0") --non-interactive  # Automated setup"
    echo
}

# Show help before setting strict error handling
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
esac

# Check Bash version (need 4.0+ for associative arrays)
if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
    echo "Error: This script requires Bash 4.0 or later for associative arrays"
    echo "Current version: $BASH_VERSION"
    echo "On macOS: brew install bash"
    echo "Then use: /usr/local/bin/bash $0 $*"
    exit 1
fi

# Set strict error handling
set -eo pipefail

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"

# Configuration
readonly SCRIPT_DIR="$PI_GATEWAY_ROOT"
readonly CONFIG_FILE="$SCRIPT_DIR/config/setup.conf"
readonly SETUP_STATE_FILE="/tmp/pi-gateway-setup-state.json"

# Setup phases and components
readonly PHASES=(
    "requirements"
    "dependencies"
    "hardening"
    "ssh"
    "vpn"
    "firewall"
    "remote-desktop"
    "ddns"
)

declare -A PHASE_DESCRIPTIONS=(
    ["requirements"]="System Requirements & Validation"
    ["dependencies"]="Dependency Installation"
    ["hardening"]="System Security Hardening"
    ["ssh"]="SSH Hardening & Configuration"
    ["vpn"]="WireGuard VPN Setup"
    ["firewall"]="Advanced Firewall Configuration"
    ["remote-desktop"]="Remote Desktop Setup"
    ["ddns"]="Dynamic DNS Configuration"
)

declare -A PHASE_SCRIPTS=(
    ["requirements"]="scripts/check-requirements.sh"
    ["dependencies"]="scripts/install-dependencies.sh"
    ["hardening"]="scripts/system-hardening.sh"
    ["ssh"]="scripts/ssh-setup.sh"
    ["vpn"]="scripts/vpn-setup.sh"
    ["firewall"]="scripts/firewall-setup.sh"
    ["remote-desktop"]="scripts/remote-desktop.sh"
    ["ddns"]="scripts/ddns-setup.sh"
)

# Setup options
INTERACTIVE_MODE=true
DRY_RUN="${DRY_RUN:-false}"
VERBOSE_MODE=false
SELECTED_PHASES=()
SETUP_CONFIG=()

# Setup state tracking
declare -A PHASE_STATUS=()
SETUP_START_TIME=""
SETUP_ERROR_COUNT=0

# Override error function to track setup errors
error() {
    echo -e "  ${RED}✗${NC} $1" >&2
    log "ERROR" "$1"
    ((SETUP_ERROR_COUNT++))
}

# Enhanced progress tracking with visual indicators
show_progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))

    # Build progress bar
    local bar=""
    for ((i=0; i<completed; i++)); do bar+="█"; done
    for ((i=0; i<remaining; i++)); do bar+="░"; done

    echo -e "  ${CYAN}Progress: [${GREEN}$bar${CYAN}] ${WHITE}$percentage%${CYAN} ($current/$total)${NC}"
}

show_phase_progress() {
    local current_phase=$1
    local total_phases=$2
    local phase_name="$3"
    local phase_description="$4"

    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    show_progress_bar "$current_phase" "$total_phases"
    echo -e "  ${WHITE}Current Phase:${NC} ${CYAN}$phase_name${NC}"
    echo -e "  ${WHITE}Description:${NC} $phase_description"

    # Estimate time remaining
    if [[ -n "$SETUP_START_TIME" && $current_phase -gt 1 ]]; then
        local elapsed=$(($(date +%s) - SETUP_START_TIME))
        local avg_time_per_phase=$((elapsed / (current_phase - 1)))
        local remaining_phases=$((total_phases - current_phase + 1))
        local estimated_remaining=$((avg_time_per_phase * remaining_phases))

        if [[ $estimated_remaining -gt 60 ]]; then
            local minutes=$((estimated_remaining / 60))
            echo -e "  ${WHITE}Estimated remaining:${NC} ${YELLOW}~${minutes} minutes${NC}"
        else
            echo -e "  ${WHITE}Estimated remaining:${NC} ${YELLOW}~${estimated_remaining} seconds${NC}"
        fi
    fi
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo
}

# Sub-phase progress for individual scripts
show_subphase_progress() {
    local message="$1"
    local step="${2:-}"
    local total_steps="${3:-}"

    if [[ -n "$step" && -n "$total_steps" ]]; then
        local sub_percentage=$((step * 100 / total_steps))
        echo -e "  ${CYAN}📋${NC} $message ${GRAY}[$step/$total_steps - $sub_percentage%]${NC}"
    else
        echo -e "  ${CYAN}📋${NC} $message"
    fi
}

# Display functions
print_header() {
    clear
    echo
    echo -e "${BLUE}████████████████████████████████████████████████████████████${NC}"
    echo -e "${BLUE}█                                                          █${NC}"
    echo -e "${BLUE}█                    ${WHITE}Pi Gateway Setup${NC}${BLUE}                    █${NC}"
    echo -e "${BLUE}█                                                          █${NC}"
    echo -e "${BLUE}█        ${CYAN}Comprehensive Homelab Bootstrap System${NC}${BLUE}        █${NC}"
    echo -e "${BLUE}█                                                          █${NC}"
    echo -e "${BLUE}████████████████████████████████████████████████████████████${NC}"
    echo
    echo -e "${CYAN}🚀 Welcome to Pi Gateway - Your Secure Homelab Foundation${NC}"
    echo
}

print_phase_header() {
    local phase="$1"
    local description="${PHASE_DESCRIPTIONS[$phase]}"

    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║  ${WHITE}Phase: $description${NC}${BLUE}$(printf "%*s" $((40 - ${#description})) "")║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_summary() {
    local duration="$1"

    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║  ${WHITE}Pi Gateway Setup Complete!${NC}${GREEN}$(printf "%*s" 27 "")║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}📊 Setup Summary:${NC}"
    echo -e "  ${YELLOW}Duration:${NC} $duration"
    echo -e "  ${YELLOW}Phases Completed:${NC} ${#SELECTED_PHASES[@]}"
    echo -e "  ${YELLOW}Errors:${NC} $SETUP_ERROR_COUNT"
    echo
}

# Configuration functions
load_default_config() {
    SETUP_CONFIG=(
        "ENABLE_SSH=true"
        "ENABLE_VPN=true"
        "ENABLE_FIREWALL=true"
        "ENABLE_REMOTE_DESKTOP=false"
        "ENABLE_DDNS=false"
        "SSH_PORT=2222"
        "VPN_PORT=51820"
        "VNC_PORT=5900"
        "RDP_PORT=3389"
    )
}

load_config_file() {
    if [[ -f "$CONFIG_FILE" ]]; then
        info "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        success "Configuration loaded successfully"
    else
        info "No configuration file found, using defaults"
        load_default_config
    fi
}

save_setup_state() {
    local state_json=""

    # Build JSON manually to avoid heredoc issues
    state_json="{"
    state_json+="\"setup_start_time\": \"$SETUP_START_TIME\","
    state_json+="\"phases\": ["

    local first=true
    for phase in "${PHASES[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            state_json+=","
        fi
        state_json+="{\"name\": \"$phase\","
        state_json+="\"description\": \"${PHASE_DESCRIPTIONS[$phase]}\","
        state_json+="\"status\": \"${PHASE_STATUS[$phase]:-pending}\","
        state_json+="\"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"}"
    done

    state_json+="],"
    state_json+="\"error_count\": $SETUP_ERROR_COUNT"
    state_json+="}"

    echo "$state_json" > "$SETUP_STATE_FILE"
}

# Interactive setup functions
show_welcome_screen() {
    print_header

    echo -e "${YELLOW}🔒 About Pi Gateway:${NC}"
    echo -e "Pi Gateway transforms your Raspberry Pi into a secure homelab foundation"
    echo -e "with enterprise-grade security, VPN access, and remote management."
    echo
    echo -e "${YELLOW}🛡️  Security Features:${NC}"
    echo -e "  • SSH hardening with key-based authentication"
    echo -e "  • WireGuard VPN server with client management"
    echo -e "  • Advanced firewall with intrusion detection"
    echo -e "  • System hardening and security monitoring"
    echo
    echo -e "${YELLOW}🌐 Remote Access:${NC}"
    echo -e "  • Secure VNC and RDP remote desktop"
    echo -e "  • Dynamic DNS for external connectivity"
    echo -e "  • Encrypted connections and network isolation"
    echo
    echo -e "${YELLOW}⚙️  Management:${NC}"
    echo -e "  • Automated service monitoring"
    echo -e "  • Configuration backup and restore"
    echo -e "  • Comprehensive logging and alerting"
    echo
}

select_installation_mode() {
    echo -e "${CYAN}📋 Installation Mode Selection:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} Full Installation (Recommended)"
    echo -e "     Complete Pi Gateway with all security features"
    echo
    echo -e "  ${YELLOW}2.${NC} Core Security Only"
    echo -e "     SSH, VPN, and Firewall without remote desktop/DNS"
    echo
    echo -e "  ${YELLOW}3.${NC} Custom Installation"
    echo -e "     Select individual components to install"
    echo
    echo -e "  ${YELLOW}4.${NC} Dry Run Mode"
    echo -e "     Test installation without making system changes"
    echo

    local choice
    while true; do
        read -r -p "Select installation mode (1-4): " choice
        case $choice in
            1)
                SELECTED_PHASES=("${PHASES[@]}")
                info "Selected: Full Installation"
                break
                ;;
            2)
                SELECTED_PHASES=("requirements" "dependencies" "hardening" "ssh" "vpn" "firewall")
                info "Selected: Core Security Only"
                break
                ;;
            3)
                select_custom_components
                break
                ;;
            4)
                DRY_RUN=true
                SELECTED_PHASES=("${PHASES[@]}")
                info "Selected: Dry Run Mode (Full Installation)"
                break
                ;;
            *)
                warning "Invalid selection. Please choose 1-4."
                ;;
        esac
    done
}

select_custom_components() {
    echo
    echo -e "${CYAN}🛠️  Custom Component Selection:${NC}"
    echo

    # Always include core components
    SELECTED_PHASES=("requirements" "dependencies" "hardening")

    local components=(
        "ssh:SSH Hardening & Key-based Authentication"
        "vpn:WireGuard VPN Server & Client Management"
        "firewall:Advanced Firewall & Intrusion Detection"
        "remote-desktop:VNC/RDP Remote Desktop Access"
        "ddns:Dynamic DNS for External Connectivity"
    )

    for component in "${components[@]}"; do
        local comp_key="${component%%:*}"
        local comp_desc="${component#*:}"

        local response
        while true; do
            read -r -p "Install $comp_desc? (y/n): " response
            case $response in
                [Yy]*)
                    SELECTED_PHASES+=("$comp_key")
                    info "Added: $comp_desc"
                    break
                    ;;
                [Nn]*)
                    warning "Skipped: $comp_desc"
                    break
                    ;;
                *)
                    warning "Please answer y or n."
                    ;;
            esac
        done
    done
}

confirm_installation() {
    echo
    echo -e "${CYAN}📋 Installation Summary:${NC}"
    echo
    echo -e "${YELLOW}Selected Components:${NC}"
    for phase in "${SELECTED_PHASES[@]}"; do
        echo -e "  ✓ ${PHASE_DESCRIPTIONS[$phase]}"
    done
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${PURPLE}🧪 DRY RUN MODE: No actual system changes will be made${NC}"
        echo
    fi

    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo -e "  • This installation requires sudo privileges"
    echo -e "  • Internet connection is required for package downloads"
    echo -e "  • Installation may take 10-30 minutes depending on components"
    echo -e "  • Existing configurations will be backed up automatically"
    echo

    local response
    while true; do
        read -r -p "Proceed with installation? (y/n): " response
        case $response in
            [Yy]*)
                return 0
                ;;
            [Nn]*)
                info "Installation cancelled by user"
                exit 0
                ;;
            *)
                warning "Please answer y or n."
                ;;
        esac
    done
}

# Phase execution functions
execute_phase() {
    local phase="$1"
    local script="${PHASE_SCRIPTS[$phase]}"
    local description="${PHASE_DESCRIPTIONS[$phase]}"

    print_phase_header "$phase"

    PHASE_STATUS[$phase]="running"
    save_setup_state

    progress "Starting: $description"

    if [[ ! -f "$script" ]]; then
        error "Script not found: $script"
        PHASE_STATUS[$phase]="failed"
        return 1
    fi

    # Set environment variables for the script
    export DRY_RUN
    export VERBOSE_DRY_RUN="$VERBOSE_MODE"

    local start_time
    start_time=$(date +%s)

    if [[ "$DRY_RUN" == "true" ]]; then
        progress "Executing in dry-run mode: $script"
    else
        progress "Executing: $script"
    fi

    # Execute the phase script
    if "$script"; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        success "Completed: $description (${duration}s)"
        PHASE_STATUS[$phase]="completed"
        save_setup_state
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        error "Failed: $description (${duration}s)"
        PHASE_STATUS[$phase]="failed"
        save_setup_state
        return 1
    fi
}

# Main setup orchestration
run_setup_phases() {
    local total_phases=${#SELECTED_PHASES[@]}
    local completed_phases=0
    local failed_phases=0

    # Set setup start time for time estimation
    SETUP_START_TIME=$(date +%s)

    progress "Starting Pi Gateway setup with $total_phases phases"
    echo -e "  ${WHITE}Total phases to complete:${NC} ${CYAN}$total_phases${NC}"
    echo

    for phase in "${SELECTED_PHASES[@]}"; do
        ((completed_phases++))

        # Show enhanced progress for current phase
        local phase_description="${PHASE_DESCRIPTIONS[$phase]}"
        show_phase_progress "$completed_phases" "$total_phases" "$phase" "$phase_description"

        if execute_phase "$phase"; then
            success "Phase completed successfully: $phase"
        else
            error "Phase failed: $phase"
            ((failed_phases++))

            if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                echo
                warning "Phase '$phase' failed. Do you want to continue with the next phase?"
                local response
                while true; do
                    read -r -p "Continue setup? (y/n): " response
                    case $response in
                        [Yy]*)
                            warning "Continuing with remaining phases..."
                            break
                            ;;
                        [Nn]*)
                            error "Setup aborted by user after failure"
                            return 1
                            ;;
                        *)
                            warning "Please answer y or n."
                            ;;
                    esac
                done
            else
                error "Non-interactive mode: aborting setup after failure"
                return 1
            fi
        fi
    done

    if [[ $failed_phases -eq 0 ]]; then
        success "All phases completed successfully!"
        return 0
    else
        warning "Setup completed with $failed_phases failed phases"
        return 1
    fi
}

# Post-installation functions
show_connection_info() {
    echo
    echo -e "${GREEN}🔗 Connection Information:${NC}"
    echo

    local local_ip
    if [[ "$DRY_RUN" == "true" ]]; then
        local_ip="192.168.1.100"
    else
        local_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "192.168.1.100")
    fi

    echo -e "${YELLOW}SSH Access:${NC}"
    echo -e "  Local:  ssh -p 2222 pi@$local_ip"
    echo -e "  Remote: ssh -p 2222 pi@your-domain.duckdns.org"
    echo

    if [[ " ${SELECTED_PHASES[*]} " =~ " vpn " ]]; then
        echo -e "${YELLOW}VPN Access:${NC}"
        echo -e "  Server: $local_ip:51820"
        echo -e "  Client: Use 'wg-add-client' to create configurations"
        echo
    fi

    if [[ " ${SELECTED_PHASES[*]} " =~ " remote-desktop " ]]; then
        echo -e "${YELLOW}Remote Desktop:${NC}"
        echo -e "  VNC: $local_ip:5900 (via VPN only)"
        echo -e "  RDP: $local_ip:3389 (via VPN only)"
        echo
    fi
}

show_next_steps() {
    echo -e "${GREEN}🚀 Next Steps:${NC}"
    echo

    echo -e "${YELLOW}1. Configure Your Router:${NC}"
    echo -e "   • Forward port 2222 for SSH access"
    echo -e "   • Forward port 51820 for VPN access"
    echo

    echo -e "${YELLOW}2. Set Up VPN Clients:${NC}"
    echo -e "   • Add clients: wg-add-client laptop"
    echo -e "   • Copy client configs from /etc/wireguard/clients/"
    echo

    echo -e "${YELLOW}3. Test Connectivity:${NC}"
    echo -e "   • Test SSH: ssh -p 2222 pi@your-external-ip"
    echo -e "   • Test VPN: Connect using WireGuard client"
    echo

    echo -e "${YELLOW}4. Monitor Services:${NC}"
    echo -e "   • Check status: systemctl status ssh wireguard@wg0"
    echo -e "   • View logs: journalctl -f"
    echo
}

# Utility functions
cleanup_on_exit() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo
        error "Setup failed with exit code $exit_code"
        echo -e "${YELLOW}🔍 Troubleshooting:${NC}"
        echo -e "  • Check log file: $LOG_FILE"
        echo -e "  • Review setup state: $SETUP_STATE_FILE"
        echo -e "  • Run individual scripts manually for debugging"
    fi

    save_setup_state
}


# Argument parsing
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -n|--non-interactive)
                INTERACTIVE_MODE=false
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Pre-flight system validation
run_preflight_checks() {
    echo
    progress "Running pre-flight system validation..."

    # Source the pre-flight check script
    local preflight_script="$SCRIPT_DIR/scripts/pre-flight-check.sh"

    if [[ -f "$preflight_script" ]]; then
        # Run the pre-flight checks
        if bash "$preflight_script"; then
            success "Pre-flight checks completed successfully"
            echo
        else
            error "Pre-flight checks failed - system not ready for setup"
            echo
            echo -e "${YELLOW}Please resolve the issues above before running Pi Gateway setup.${NC}"
            echo -e "${WHITE}You can run the checks again with:${NC} ./scripts/pre-flight-check.sh"
            echo
            exit 1
        fi
    else
        warning "Pre-flight check script not found, proceeding with setup"
        echo -e "${WHITE}Manual verification recommended:${NC}"
        echo -e "  • Internet connectivity available"
        echo -e "  • Sufficient disk space (8GB+)"
        echo -e "  • Sudo privileges configured"
        echo
        read -p "Continue anyway? (y/N): " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            info "Setup cancelled by user"
            exit 0
        fi
    fi
}

# Main execution
main() {
    # Set up signal handlers
    trap cleanup_on_exit EXIT

    # Parse command line arguments
    parse_arguments "$@"

    # Initialize setup
    SETUP_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    log "INFO" "Starting Pi Gateway setup"

    # Load configuration
    load_config_file

    # Run pre-flight checks
    run_preflight_checks

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        # Interactive setup flow
        show_welcome_screen

        echo -n "Press Enter to continue..."
        read -r

        select_installation_mode
        confirm_installation
    else
        # Non-interactive setup
        SELECTED_PHASES=("${PHASES[@]}")
        info "Running non-interactive setup with all phases"
    fi

    # Initialize phase status
    for phase in "${PHASES[@]}"; do
        PHASE_STATUS[$phase]="pending"
    done

    # Execute setup phases
    local setup_start_timestamp
    setup_start_timestamp=$(date +%s)

    if run_setup_phases; then
        local setup_end_timestamp
        setup_end_timestamp=$(date +%s)
        local setup_duration=$((setup_end_timestamp - setup_start_timestamp))
        local duration_formatted
        duration_formatted=$(printf '%02d:%02d:%02d' $((setup_duration/3600)) $((setup_duration%3600/60)) $((setup_duration%60)))

        print_summary "$duration_formatted"
        show_connection_info
        show_next_steps

        success "Pi Gateway setup completed successfully!"
        return 0
    else
        error "Pi Gateway setup failed"
        return 1
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi