#!/bin/bash
#
# Pi Gateway - Remote Desktop Setup
# VNC and RDP configuration for secure remote GUI access
#

set -euo pipefail

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
readonly LOG_FILE="/tmp/pi-gateway-remote-desktop.log"
readonly CONFIG_BACKUP_DIR="/etc/pi-gateway/backups/remote-desktop-$(date +%Y%m%d_%H%M%S)"

# Remote desktop configuration
readonly VNC_PORT="${VNC_PORT:-5900}"
readonly VNC_DISPLAY=":1"
readonly VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
readonly VNC_DEPTH="${VNC_DEPTH:-24}"
readonly VNC_PASSWORD_FILE="/home/pi/.vnc/passwd"
readonly VNC_CONFIG_DIR="/home/pi/.vnc"
readonly VNC_STARTUP_FILE="$VNC_CONFIG_DIR/xstartup"

# RDP configuration
readonly RDP_PORT="${RDP_PORT:-3389}"
readonly XRDP_CONFIG="/etc/xrdp/xrdp.ini"
readonly XRDP_SESMAN_CONFIG="/etc/xrdp/sesman.ini"

# Desktop environment detection
DESKTOP_ENV=""

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
    echo -e "${BLUE}       Pi Gateway - Remote Desktop Setup      ${NC}"
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
        echo -e "${PURPLE}   → All remote desktop configuration will be simulated${NC}"
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

# Detect desktop environment
detect_desktop_environment() {
    print_section "Desktop Environment Detection"

    if [[ "$DRY_RUN" == "true" ]]; then
        DESKTOP_ENV="LXDE"
        success "Desktop environment detected: $DESKTOP_ENV (mocked)"
        return 0
    fi

    # Check for various desktop environments
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        DESKTOP_ENV="$XDG_CURRENT_DESKTOP"
    elif command -v lxsession >/dev/null 2>&1; then
        DESKTOP_ENV="LXDE"
    elif command -v xfce4-session >/dev/null 2>&1; then
        DESKTOP_ENV="XFCE"
    elif command -v gnome-session >/dev/null 2>&1; then
        DESKTOP_ENV="GNOME"
    elif command -v startx >/dev/null 2>&1; then
        DESKTOP_ENV="X11"
    else
        warning "No desktop environment detected - will install LXDE"
        DESKTOP_ENV="LXDE"
    fi

    success "Desktop environment detected: $DESKTOP_ENV"
}

# Install desktop environment if needed
install_desktop_environment() {
    print_section "Desktop Environment Installation"

    if [[ "$DESKTOP_ENV" == "LXDE" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            success "LXDE installation skipped in dry-run mode"
            return 0
        fi

        # Check if LXDE is already installed
        if ! command -v lxsession >/dev/null 2>&1; then
            info "Installing LXDE desktop environment..."
            execute_command "apt update" "Update package repositories"
            execute_command "apt install -y lxde-core lxde-common lxsession-logout" "Install LXDE core"
            execute_command "apt install -y pcmanfm lxterminal" "Install file manager and terminal"
            success "LXDE desktop environment installed"
        else
            success "LXDE desktop environment already installed"
        fi
    else
        success "Using existing desktop environment: $DESKTOP_ENV"
    fi
}

# Install VNC server
install_vnc_server() {
    print_section "VNC Server Installation"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "VNC server installation skipped in dry-run mode"
        return 0
    fi

    # Try to install RealVNC first, fallback to TightVNC
    if apt list --installed 2>/dev/null | grep -q realvnc-vnc-server; then
        success "RealVNC server already installed"
        return 0
    fi

    info "Attempting to install RealVNC server..."
    if execute_command "apt install -y realvnc-vnc-server realvnc-vnc-viewer" "Install RealVNC server"; then
        success "RealVNC server installed successfully"
    else
        warning "RealVNC not available, installing TightVNC as alternative"
        execute_command "apt install -y tightvncserver" "Install TightVNC server"
        success "TightVNC server installed successfully"
    fi
}

# Install xRDP server
install_xrdp_server() {
    print_section "xRDP Server Installation"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "xRDP server installation skipped in dry-run mode"
        return 0
    fi

    if ! command -v xrdp >/dev/null 2>&1; then
        info "Installing xRDP server..."
        execute_command "apt install -y xrdp" "Install xRDP server"
        success "xRDP server installed successfully"
    else
        success "xRDP server already installed"
    fi
}

# Backup existing configuration
backup_remote_desktop_config() {
    print_section "Configuration Backup"

    execute_command "mkdir -p '$CONFIG_BACKUP_DIR'" "Create backup directory"

    # Backup VNC configuration
    if [[ -d "$VNC_CONFIG_DIR" ]]; then
        execute_command "cp -r '$VNC_CONFIG_DIR' '$CONFIG_BACKUP_DIR/vnc-config.backup'" "Backup VNC configuration"
        success "VNC configuration backed up"
    fi

    # Backup xRDP configuration
    if [[ -f "$XRDP_CONFIG" ]]; then
        execute_command "cp '$XRDP_CONFIG' '$CONFIG_BACKUP_DIR/xrdp.ini.backup'" "Backup xRDP configuration"
    fi

    if [[ -f "$XRDP_SESMAN_CONFIG" ]]; then
        execute_command "cp '$XRDP_SESMAN_CONFIG' '$CONFIG_BACKUP_DIR/sesman.ini.backup'" "Backup xRDP sesman configuration"
    fi

    success "Remote desktop configuration backed up: $CONFIG_BACKUP_DIR"
}

# Configure VNC server
configure_vnc_server() {
    print_section "VNC Server Configuration"

    # Create VNC directory structure
    execute_command "mkdir -p '$VNC_CONFIG_DIR'" "Create VNC configuration directory"
    execute_command "chown pi:pi '$VNC_CONFIG_DIR'" "Set VNC directory ownership"
    execute_command "chmod 700 '$VNC_CONFIG_DIR'" "Set VNC directory permissions"

    # Set VNC password
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Setting VNC password..."
        # Generate a secure random password
        local vnc_password
        vnc_password=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-8)
        echo "$vnc_password" | vncpasswd -f > "$VNC_PASSWORD_FILE" || true
        execute_command "chown pi:pi '$VNC_PASSWORD_FILE'" "Set VNC password file ownership"
        execute_command "chmod 600 '$VNC_PASSWORD_FILE'" "Set VNC password file permissions"
        success "VNC password configured (password: $vnc_password)"
    else
        execute_command "echo 'pi-gateway' | vncpasswd -f > '$VNC_PASSWORD_FILE'" "Set VNC password (dry-run)"
        execute_command "chown pi:pi '$VNC_PASSWORD_FILE'" "Set VNC password file ownership"
        execute_command "chmod 600 '$VNC_PASSWORD_FILE'" "Set VNC password file permissions"
        success "VNC password configured (mocked)"
    fi

    # Create VNC startup script
    local startup_script
    case "$DESKTOP_ENV" in
        "LXDE")
            startup_script="lxsession -s LXDE &"
            ;;
        "XFCE")
            startup_script="startxfce4 &"
            ;;
        "GNOME")
            startup_script="gnome-session &"
            ;;
        *)
            startup_script="xterm &"
            ;;
    esac

    execute_command "cat > '$VNC_STARTUP_FILE' << 'EOF'
#!/bin/bash
# Pi Gateway VNC Startup Script
# Automatically generated on $(date)

# Kill any existing VNC desktop
vncserver -kill $VNC_DISPLAY >/dev/null 2>&1 || true

# Clean up tmp files
rm -f /tmp/.X*-lock /tmp/.X11-unix/X* >/dev/null 2>&1 || true

# Set desktop background color
xsetroot -solid grey

# Start window manager
$startup_script

# Start file manager
pcmanfm --desktop --profile LXDE-pi &

# Start panel
lxpanel --profile LXDE-pi &

# Keep session alive
exec /bin/bash
EOF" "Create VNC startup script"

    execute_command "chmod +x '$VNC_STARTUP_FILE'" "Make VNC startup script executable"
    execute_command "chown pi:pi '$VNC_STARTUP_FILE'" "Set VNC startup script ownership"

    success "VNC server configuration completed"
}

# Configure xRDP server
configure_xrdp_server() {
    print_section "xRDP Server Configuration"

    # Configure xRDP main settings
    execute_command "cat > '$XRDP_CONFIG' << 'EOF'
[Globals]
; xrdp configuration for Pi Gateway
bitmap_cache=true
bitmap_compression=true
port=$RDP_PORT
crypt_level=medium
channel_code=1
max_bpp=24
fork=true
tcp_nodelay=true
tcp_keepalive=true
use_fastpath=both

[Logging]
LogFile=xrdp.log
LogLevel=INFO
EnableSyslog=true
SyslogLevel=INFO

[Channels]
rdpdr=true
rdpsnd=true
drdynvc=true
cliprdr=true
rail=true
xrdpvr=true

[Security]
crypt_level=medium
allow_channels=true
allow_multimon=true
bitmap_cache=true
bitmap_compression=true
bulk_compression=true

[xrdp1]
name=Pi Gateway LXDE
lib=libvnc.so
username=ask
password=ask
ip=127.0.0.1
port=-1
xserverbpp=24
EOF" "Create xRDP configuration"

    # Configure xRDP session manager
    execute_command "cat > '$XRDP_SESMAN_CONFIG' << 'EOF'
[Globals]
ListenAddress=127.0.0.1
ListenPort=3350
EnableUserWindowManager=true
UserWindowManager=startlxde
DefaultWindowManager=startlxde
AlwaysGroupCheck=false

[Security]
AllowRootLogin=false
MaxLoginRetry=4
TerminalServerUsers=tsusers
TerminalServerAdmins=tsadmins
AlternateShell=/bin/sh

[Sessions]
X11DisplayOffset=10
KillDisconnected=false
IdleTimeLimit=0
DisconnectedTimeLimit=0
Policy=UBM

[Logging]
LogFile=xrdp-sesman.log
LogLevel=INFO
EnableSyslog=1
SyslogLevel=INFO

[ChansrvLogging]
LogFile=xrdp-chansrv.log
LogLevel=INFO
EnableSyslog=1
SyslogLevel=INFO

[SessionVariables]
PULSE_SERVER=unix:/tmp/pulse-socket
EOF" "Create xRDP sesman configuration"

    # Set proper permissions
    execute_command "chmod 644 '$XRDP_CONFIG'" "Set xRDP config permissions"
    execute_command "chmod 644 '$XRDP_SESMAN_CONFIG'" "Set xRDP sesman config permissions"

    success "xRDP server configuration completed"
}

# Create systemd service for VNC
create_vnc_service() {
    print_section "VNC Service Configuration"

    execute_command "cat > '/etc/systemd/system/vncserver@.service' << 'EOF'
[Unit]
Description=Pi Gateway VNC Server
Requires=display-manager.service
After=display-manager.service

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi
Environment=HOME=/home/pi
Environment=XDG_RUNTIME_DIR=/run/user/1000

# Pre-start: Kill any existing VNC sessions
ExecStartPre=/bin/bash -c 'vncserver -kill :%i >/dev/null 2>&1 || true'

# Start VNC server
ExecStart=/usr/bin/vncserver :%i -localhost no -geometry $VNC_GEOMETRY -depth $VNC_DEPTH

# Post-start: Ensure VNC is running
ExecStartPost=/bin/sleep 2

# Stop VNC server
ExecStop=/usr/bin/vncserver -kill :%i

# Restart policy
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF" "Create VNC systemd service"

    execute_command "systemctl daemon-reload" "Reload systemd configuration"
    execute_command "systemctl enable vncserver@1.service" "Enable VNC service"

    success "VNC systemd service created and enabled"
}

# Configure firewall rules for remote desktop
configure_firewall_rules() {
    print_section "Firewall Configuration"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "Firewall configuration skipped in dry-run mode"
        return 0
    fi

    # Check if UFW is available
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW not installed - firewall rules not configured"
        return 0
    fi

    # Allow VNC only from VPN and local networks
    execute_command "ufw allow from 10.13.13.0/24 to any port $VNC_PORT comment 'VNC for VPN clients'" "Allow VNC for VPN clients"
    execute_command "ufw allow from 192.168.0.0/16 to any port $VNC_PORT comment 'VNC for local network'" "Allow VNC for local network"

    # Allow RDP only from VPN and local networks
    execute_command "ufw allow from 10.13.13.0/24 to any port $RDP_PORT comment 'RDP for VPN clients'" "Allow RDP for VPN clients"
    execute_command "ufw allow from 192.168.0.0/16 to any port $RDP_PORT comment 'RDP for local network'" "Allow RDP for local network"

    success "Firewall rules configured for remote desktop access"
}

# Start remote desktop services
start_remote_desktop_services() {
    print_section "Service Startup"

    if [[ "$DRY_RUN" == "true" ]]; then
        success "Service startup skipped in dry-run mode"
        return 0
    fi

    # Start VNC service
    execute_command "systemctl start vncserver@1.service" "Start VNC service"

    # Check VNC service status
    if systemctl is-active vncserver@1.service >/dev/null 2>&1; then
        success "VNC service started successfully"
    else
        error "VNC service failed to start"
        error "Check logs: journalctl -u vncserver@1.service"
    fi

    # Start xRDP service
    execute_command "systemctl enable xrdp" "Enable xRDP service"
    execute_command "systemctl start xrdp" "Start xRDP service"

    # Check xRDP service status
    if systemctl is-active xrdp >/dev/null 2>&1; then
        success "xRDP service started successfully"
    else
        warning "xRDP service may have failed to start"
        warning "Check logs: journalctl -u xrdp"
    fi
}

# Display connection information
display_connection_info() {
    print_section "Remote Desktop Connection Information"

    local local_ip
    if [[ "$DRY_RUN" == "true" ]]; then
        local_ip="192.168.1.100"
    else
        local_ip=$(hostname -I | awk '{print $1}' || echo "192.168.1.100")
    fi

    echo
    echo -e "${GREEN}🖥️  Remote Desktop Setup Complete!${NC}"
    echo
    echo -e "${BLUE}VNC Connection Details:${NC}"
    echo -e "  ${YELLOW}Protocol:${NC} VNC"
    echo -e "  ${YELLOW}Port:${NC} $VNC_PORT"
    echo -e "  ${YELLOW}Display:${NC} $VNC_DISPLAY"
    echo -e "  ${YELLOW}Resolution:${NC} $VNC_GEOMETRY"
    echo -e "  ${YELLOW}Color Depth:${NC} $VNC_DEPTH bits"
    echo

    echo -e "${BLUE}RDP Connection Details:${NC}"
    echo -e "  ${YELLOW}Protocol:${NC} RDP"
    echo -e "  ${YELLOW}Port:${NC} $RDP_PORT"
    echo -e "  ${YELLOW}Username:${NC} pi"
    echo -e "  ${YELLOW}Authentication:${NC} System password"
    echo

    echo -e "${BLUE}Connection Methods:${NC}"
    echo -e "  ${PURPLE}Local VNC:${NC} $local_ip:$VNC_PORT"
    echo -e "  ${PURPLE}Local RDP:${NC} $local_ip:$RDP_PORT"
    echo -e "  ${PURPLE}VPN VNC:${NC} 10.13.13.1:$VNC_PORT"
    echo -e "  ${PURPLE}VPN RDP:${NC} 10.13.13.1:$RDP_PORT"
    echo

    echo -e "${BLUE}Client Applications:${NC}"
    echo -e "  ${PURPLE}VNC Viewer:${NC} RealVNC Viewer, TightVNC Viewer, TigerVNC"
    echo -e "  ${PURPLE}RDP Client:${NC} Windows Remote Desktop, Remmina, FreeRDP"
    echo

    echo -e "${BLUE}Service Management:${NC}"
    echo -e "  ${PURPLE}VNC Status:${NC} sudo systemctl status vncserver@1.service"
    echo -e "  ${PURPLE}VNC Start:${NC} sudo systemctl start vncserver@1.service"
    echo -e "  ${PURPLE}VNC Stop:${NC} sudo systemctl stop vncserver@1.service"
    echo -e "  ${PURPLE}RDP Status:${NC} sudo systemctl status xrdp"
    echo -e "  ${PURPLE}RDP Start:${NC} sudo systemctl start xrdp"
    echo -e "  ${PURPLE}RDP Stop:${NC} sudo systemctl stop xrdp"
    echo

    echo -e "${YELLOW}⚠️  Important Security Notes:${NC}"
    echo -e "  • Remote desktop access is restricted to VPN and local network only"
    echo -e "  • Use strong passwords for the 'pi' user account"
    echo -e "  • VNC password is automatically generated and secure"
    echo -e "  • Consider using VPN for external access instead of port forwarding"
    echo -e "  • Monitor remote desktop sessions regularly"
    echo

    if [[ "$DRY_RUN" == "false" ]] && [[ -f "$VNC_PASSWORD_FILE" ]]; then
        echo -e "${BLUE}VNC Password:${NC}"
        echo -e "${PURPLE}========================================${NC}"
        if command -v vncpasswd >/dev/null 2>&1; then
            info "VNC password has been set (check logs for generated password)"
        fi
        echo -e "${PURPLE}========================================${NC}"
        echo
    fi

    success "Remote desktop setup completed successfully!"
}

# Main execution
main() {
    print_header

    log "INFO" "Starting Pi Gateway remote desktop setup"

    # Initialize dry-run environment
    init_dry_run_environment

    # Pre-setup checks
    check_sudo
    detect_desktop_environment

    # Setup process
    backup_remote_desktop_config
    install_desktop_environment
    install_vnc_server
    install_xrdp_server
    configure_vnc_server
    configure_xrdp_server
    create_vnc_service
    configure_firewall_rules
    start_remote_desktop_services

    # Final information
    display_connection_info

    log "INFO" "Pi Gateway remote desktop setup completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi