#!/bin/bash
#
# Pi Gateway Container & Virtualization Support
# Docker, Podman, and container orchestration setup
#

set -euo pipefail

# Check Bash version compatibility
if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
    echo "Error: This script requires Bash 4.0+ for associative arrays"
    echo "Current version: $BASH_VERSION"
    exit 1
fi

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly LOG_DIR="$PROJECT_ROOT/logs"
readonly STATE_DIR="$PROJECT_ROOT/state"
readonly CONTAINER_CONFIG="$CONFIG_DIR/container-support.conf"
readonly CONTAINER_STATE="$STATE_DIR/container-support.json"
readonly CONTAINER_LOG="$LOG_DIR/container-support.log"

# Container directories
readonly CONTAINER_DATA_DIR="$PROJECT_ROOT/data/containers"
readonly DOCKER_COMPOSE_DIR="$PROJECT_ROOT/containers"
readonly CONTAINER_CONFIGS_DIR="$CONFIG_DIR/containers"

# Logging functions
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$CONTAINER_LOG"; }
success() { echo -e "  ${GREEN}✓${NC} $1" | tee -a "$CONTAINER_LOG"; }
error() { echo -e "  ${RED}✗${NC} $1" | tee -a "$CONTAINER_LOG"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1" | tee -a "$CONTAINER_LOG"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1" | tee -a "$CONTAINER_LOG"; }
debug() { [[ "${DEBUG:-}" == "true" ]] && echo -e "  ${PURPLE}🔍${NC} $1" | tee -a "$CONTAINER_LOG"; }

# Initialize container support
initialize_container_support() {
    log "Initializing container support system..."

    # Create required directories
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$STATE_DIR" "$CONTAINER_DATA_DIR" "$DOCKER_COMPOSE_DIR" "$CONTAINER_CONFIGS_DIR"

    # Create default configuration if it doesn't exist
    if [[ ! -f "$CONTAINER_CONFIG" ]]; then
        create_default_config
    fi

    # Initialize state file
    if [[ ! -f "$CONTAINER_STATE" ]]; then
        echo '{"last_run": "", "runtime": "", "installed_services": {}, "container_status": {}}' > "$CONTAINER_STATE"
    fi

    success "Container support system initialized"
}

# Create default container configuration
create_default_config() {
    cat > "$CONTAINER_CONFIG" << 'EOF'
# Pi Gateway Container Support Configuration

# Container Runtime (docker, podman, or both)
CONTAINER_RUNTIME="docker"

# Installation Options
INSTALL_DOCKER=true
INSTALL_PODMAN=false
INSTALL_DOCKER_COMPOSE=true
INSTALL_PORTAINER=true

# Resource Limits
DEFAULT_MEMORY_LIMIT="1g"
DEFAULT_CPU_LIMIT="1.0"
DEFAULT_STORAGE_LIMIT="10g"

# Network Configuration
DOCKER_BRIDGE_SUBNET="172.17.0.0/16"
CUSTOM_NETWORK_NAME="pi-gateway"
CUSTOM_NETWORK_SUBNET="172.20.0.0/16"

# Security Settings
ENABLE_ROOTLESS_DOCKER=false
ENABLE_USER_NAMESPACE=true
RESTRICT_PRIVILEGED_CONTAINERS=true

# Monitoring and Logging
ENABLE_CONTAINER_LOGGING=true
LOG_DRIVER="json-file"
LOG_MAX_SIZE="10m"
LOG_MAX_FILES="5"

# Auto-start Services
ENABLE_WATCHTOWER=true
ENABLE_TRAEFIK=false
ENABLE_NGINX_PROXY=false

# Backup Configuration
ENABLE_CONTAINER_BACKUP=true
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_RETENTION_DAYS=30
EOF

    success "Default container configuration created"
}

# Load configuration
load_config() {
    if [[ -f "$CONTAINER_CONFIG" ]]; then
        # shellcheck source=/dev/null
        source "$CONTAINER_CONFIG"
        debug "Container configuration loaded"
    else
        error "Container configuration not found: $CONTAINER_CONFIG"
        return 1
    fi
}

# Update container state
update_container_state() {
    local key="$1"
    local value="$2"
    local timestamp=$(date -Iseconds)

    # Read current state
    local current_state
    current_state=$(cat "$CONTAINER_STATE" 2>/dev/null || echo '{}')

    # Update state using jq if available, otherwise use basic JSON manipulation
    if command -v jq >/dev/null 2>&1; then
        echo "$current_state" | jq --arg key "$key" --arg value "$value" --arg time "$timestamp" \
            '.last_run = $time | .container_status[$key] = $value' > "$CONTAINER_STATE"
    else
        # Basic JSON update without jq
        echo "{\"last_run\": \"$timestamp\", \"container_status\": {\"$key\": \"$value\"}}" > "$CONTAINER_STATE"
    fi

    debug "Container state updated: $key = $value"
}

# Install Docker
install_docker() {
    info "Installing Docker..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install Docker CE"
        return
    fi

    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        info "Docker already installed: $(docker --version)"
        return
    fi

    # Install dependencies
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    # Install Docker CE
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io

    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker

    # Add pi user to docker group
    usermod -aG docker pi

    # Configure Docker daemon
    configure_docker_daemon

    success "Docker installed successfully"
    update_container_state "docker_installed" "true"
}

# Configure Docker daemon
configure_docker_daemon() {
    info "Configuring Docker daemon..."

    local docker_config="/etc/docker/daemon.json"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would configure Docker daemon in $docker_config"
        return
    fi

    # Create Docker configuration
    cat > "$docker_config" << EOF
{
  "log-driver": "${LOG_DRIVER:-json-file}",
  "log-opts": {
    "max-size": "${LOG_MAX_SIZE:-10m}",
    "max-file": "${LOG_MAX_FILES:-5}"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    {
      "base": "${CUSTOM_NETWORK_SUBNET:-172.20.0.0/16}",
      "size": 24
    }
  ],
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323",
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc"
    }
  }
}
EOF

    # Restart Docker to apply configuration
    systemctl restart docker

    success "Docker daemon configured"
}

# Install Docker Compose
install_docker_compose() {
    info "Installing Docker Compose..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install Docker Compose"
        return
    fi

    # Check if Docker Compose is already installed
    if command -v docker-compose >/dev/null 2>&1; then
        info "Docker Compose already installed: $(docker-compose --version)"
        return
    fi

    # Install Docker Compose plugin
    apt-get update
    apt-get install -y docker-compose-plugin

    # Create symlink for backward compatibility
    if [[ ! -L "/usr/local/bin/docker-compose" ]]; then
        ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    fi

    success "Docker Compose installed successfully"
    update_container_state "docker_compose_installed" "true"
}

# Install Podman
install_podman() {
    info "Installing Podman..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install Podman"
        return
    fi

    # Check if Podman is already installed
    if command -v podman >/dev/null 2>&1; then
        info "Podman already installed: $(podman --version)"
        return
    fi

    # Install Podman
    apt-get update
    apt-get install -y podman

    # Configure Podman for pi user
    configure_podman

    success "Podman installed successfully"
    update_container_state "podman_installed" "true"
}

# Configure Podman
configure_podman() {
    info "Configuring Podman..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would configure Podman"
        return
    fi

    # Create Podman configuration directory
    mkdir -p /home/pi/.config/containers

    # Configure storage for pi user
    cat > /home/pi/.config/containers/storage.conf << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/user/1000/containers"
graphroot = "/home/pi/.local/share/containers/storage"

[storage.options]
additionalimagestores = [
]

[storage.options.overlay]
mountopt = "nodev,metacopy=on"
EOF

    # Set ownership
    chown -R pi:pi /home/pi/.config/containers

    success "Podman configured"
}

# Install Portainer
install_portainer() {
    info "Installing Portainer..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install Portainer container management"
        return
    fi

    # Create Portainer volume
    docker volume create portainer_data

    # Run Portainer container
    docker run -d \
        --name portainer \
        --restart unless-stopped \
        -p 9000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest

    success "Portainer installed and running on port 9000"
    update_container_state "portainer_installed" "true"
}

# Install Watchtower for automatic updates
install_watchtower() {
    info "Installing Watchtower for automatic container updates..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would install Watchtower container updater"
        return
    fi

    # Run Watchtower container
    docker run -d \
        --name watchtower \
        --restart unless-stopped \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e WATCHTOWER_CLEANUP=true \
        -e WATCHTOWER_POLL_INTERVAL=86400 \
        containrrr/watchtower

    success "Watchtower installed for automatic container updates"
    update_container_state "watchtower_installed" "true"
}

# Create sample Docker Compose services
create_sample_services() {
    info "Creating sample Docker Compose services..."

    # Home Assistant example
    mkdir -p "$DOCKER_COMPOSE_DIR/homeassistant"
    cat > "$DOCKER_COMPOSE_DIR/homeassistant/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
    restart: unless-stopped
    privileged: true
    network_mode: host
    environment:
      - TZ=UTC
EOF

    # Node-RED example
    mkdir -p "$DOCKER_COMPOSE_DIR/nodered"
    cat > "$DOCKER_COMPOSE_DIR/nodered/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  nodered:
    container_name: nodered
    image: nodered/node-red:latest
    ports:
      - "1880:1880"
    volumes:
      - ./data:/data
    restart: unless-stopped
    environment:
      - TZ=UTC
    user: "1000:1000"
EOF

    # Grafana + InfluxDB monitoring stack
    mkdir -p "$DOCKER_COMPOSE_DIR/monitoring"
    cat > "$DOCKER_COMPOSE_DIR/monitoring/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  influxdb:
    container_name: influxdb
    image: influxdb:2.7
    ports:
      - "8086:8086"
    volumes:
      - ./influxdb-data:/var/lib/influxdb2
      - ./influxdb-config:/etc/influxdb2
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword
      - DOCKER_INFLUXDB_INIT_ORG=pi-gateway
      - DOCKER_INFLUXDB_INIT_BUCKET=metrics
    restart: unless-stopped

  grafana:
    container_name: grafana
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - ./grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    restart: unless-stopped
    depends_on:
      - influxdb

networks:
  default:
    name: pi-gateway-monitoring
EOF

    # Pi-hole DNS example
    mkdir -p "$DOCKER_COMPOSE_DIR/pihole"
    cat > "$DOCKER_COMPOSE_DIR/pihole/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "67:67/udp"
      - "8080:80/tcp"
    environment:
      TZ: 'UTC'
      WEBPASSWORD: 'admin'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
EOF

    # Create README for services
    cat > "$DOCKER_COMPOSE_DIR/README.md" << 'EOF'
# Pi Gateway Container Services

This directory contains Docker Compose configurations for common homelab services.

## Available Services

### Home Assistant
- **Path**: `homeassistant/`
- **Port**: Host network mode
- **Description**: Home automation platform

### Node-RED
- **Path**: `nodered/`
- **Port**: 1880
- **Description**: Flow-based programming for IoT

### Monitoring Stack
- **Path**: `monitoring/`
- **Ports**: InfluxDB (8086), Grafana (3000)
- **Description**: Time-series database and visualization

### Pi-hole
- **Path**: `pihole/`
- **Ports**: DNS (53), Web (8080)
- **Description**: Network-wide ad blocking

## Usage

To start a service:
```bash
cd <service-directory>
docker-compose up -d
```

To stop a service:
```bash
cd <service-directory>
docker-compose down
```

To view logs:
```bash
cd <service-directory>
docker-compose logs -f
```

## Security Notes

- Change default passwords before deploying to production
- Review port mappings for your network security requirements
- Consider using reverse proxy for HTTPS termination
- Regularly update container images
EOF

    success "Sample Docker Compose services created"
    update_container_state "sample_services_created" "true"
}

# Create container management script
create_container_manager() {
    info "Creating container management script..."

    local manager_script="$SCRIPT_DIR/container-manager.sh"

    cat > "$manager_script" << 'EOF'
#!/bin/bash
#
# Pi Gateway Container Manager
# Easy management of Docker containers and services
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DOCKER_COMPOSE_DIR="$PROJECT_ROOT/containers"

# Logging functions
success() { echo -e "  ${GREEN}✓${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

# List available services
list_services() {
    echo -e "${CYAN}📦 Available Container Services${NC}"
    echo

    if [[ ! -d "$DOCKER_COMPOSE_DIR" ]]; then
        warning "No container services directory found"
        return 1
    fi

    local services=()
    while IFS= read -r -d '' service_dir; do
        local service_name
        service_name=$(basename "$service_dir")
        services+=("$service_name")
    done < <(find "$DOCKER_COMPOSE_DIR" -maxdepth 1 -type d -name "*" ! -name "$(basename "$DOCKER_COMPOSE_DIR")" -print0)

    if [[ ${#services[@]} -eq 0 ]]; then
        warning "No services found"
        return
    fi

    for service in "${services[@]}"; do
        local service_path="$DOCKER_COMPOSE_DIR/$service"
        if [[ -f "$service_path/docker-compose.yml" ]]; then
            # Check if service is running
            if cd "$service_path" && docker-compose ps -q | grep -q .; then
                success "$service (running)"
            else
                info "$service (stopped)"
            fi
        else
            warning "$service (no docker-compose.yml)"
        fi
    done
}

# Start service
start_service() {
    local service="$1"
    local service_path="$DOCKER_COMPOSE_DIR/$service"

    if [[ ! -d "$service_path" ]]; then
        error "Service '$service' not found"
        return 1
    fi

    if [[ ! -f "$service_path/docker-compose.yml" ]]; then
        error "No docker-compose.yml found for service '$service'"
        return 1
    fi

    info "Starting service: $service"
    cd "$service_path"
    docker-compose up -d

    success "Service '$service' started"
}

# Stop service
stop_service() {
    local service="$1"
    local service_path="$DOCKER_COMPOSE_DIR/$service"

    if [[ ! -d "$service_path" ]]; then
        error "Service '$service' not found"
        return 1
    fi

    info "Stopping service: $service"
    cd "$service_path"
    docker-compose down

    success "Service '$service' stopped"
}

# Show service logs
show_logs() {
    local service="$1"
    local service_path="$DOCKER_COMPOSE_DIR/$service"

    if [[ ! -d "$service_path" ]]; then
        error "Service '$service' not found"
        return 1
    fi

    cd "$service_path"
    docker-compose logs -f
}

# Show service status
show_status() {
    local service="$1"
    local service_path="$DOCKER_COMPOSE_DIR/$service"

    if [[ ! -d "$service_path" ]]; then
        error "Service '$service' not found"
        return 1
    fi

    echo -e "${CYAN}📊 Service Status: $service${NC}"
    echo

    cd "$service_path"
    docker-compose ps
}

# Show help
show_help() {
    echo "Pi Gateway Container Manager"
    echo
    echo "Usage: $(basename "$0") <command> [service]"
    echo
    echo "Commands:"
    echo "  list                 List all available services"
    echo "  start <service>      Start a service"
    echo "  stop <service>       Stop a service"
    echo "  restart <service>    Restart a service"
    echo "  logs <service>       Show service logs"
    echo "  status <service>     Show service status"
    echo "  help                 Show this help message"
    echo
    echo "Examples:"
    echo "  $(basename "$0") list"
    echo "  $(basename "$0") start homeassistant"
    echo "  $(basename "$0") logs grafana"
    echo
}

# Main execution
main() {
    local command="${1:-}"
    local service="${2:-}"

    case $command in
        list|ls)
            list_services
            ;;
        start)
            if [[ -z "$service" ]]; then
                error "Service name required"
                exit 1
            fi
            start_service "$service"
            ;;
        stop)
            if [[ -z "$service" ]]; then
                error "Service name required"
                exit 1
            fi
            stop_service "$service"
            ;;
        restart)
            if [[ -z "$service" ]]; then
                error "Service name required"
                exit 1
            fi
            stop_service "$service"
            start_service "$service"
            ;;
        logs)
            if [[ -z "$service" ]]; then
                error "Service name required"
                exit 1
            fi
            show_logs "$service"
            ;;
        status)
            if [[ -z "$service" ]]; then
                error "Service name required"
                exit 1
            fi
            show_status "$service"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -n "$command" ]]; then
                error "Unknown command: $command"
            else
                error "No command specified"
            fi
            echo "Use '$(basename "$0") help' for available commands"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
EOF

    chmod +x "$manager_script"
    success "Container manager script created: $manager_script"
}

# Setup container networking
setup_container_networking() {
    info "Setting up container networking..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would setup container networking"
        return
    fi

    # Create custom Docker network
    local network_name="${CUSTOM_NETWORK_NAME:-pi-gateway}"
    local network_subnet="${CUSTOM_NETWORK_SUBNET:-172.20.0.0/16}"

    if ! docker network ls | grep -q "$network_name"; then
        docker network create \
            --driver bridge \
            --subnet="$network_subnet" \
            "$network_name"
        success "Created Docker network: $network_name"
    else
        info "Docker network '$network_name' already exists"
    fi

    update_container_state "networking_configured" "true"
}

# Setup container security
setup_container_security() {
    info "Configuring container security..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would configure container security"
        return
    fi

    # Configure Docker security options
    local security_opts_file="/etc/docker/seccomp-profiles/default.json"
    mkdir -p "$(dirname "$security_opts_file")"

    # Create custom seccomp profile
    cat > "$security_opts_file" << 'EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "archMap": [
        {
            "architecture": "SCMP_ARCH_X86_64",
            "subArchitectures": [
                "SCMP_ARCH_X86",
                "SCMP_ARCH_X32"
            ]
        }
    ],
    "syscalls": [
        {
            "names": [
                "accept",
                "accept4",
                "access",
                "adjtimex",
                "alarm",
                "bind",
                "brk",
                "capget",
                "capset",
                "chdir",
                "chmod",
                "chown",
                "chown32",
                "clock_getres",
                "clock_gettime",
                "clock_nanosleep",
                "close",
                "connect",
                "copy_file_range",
                "creat",
                "dup",
                "dup2",
                "dup3",
                "epoll_create",
                "epoll_create1",
                "epoll_ctl",
                "epoll_ctl_old",
                "epoll_pwait",
                "epoll_wait",
                "epoll_wait_old",
                "eventfd",
                "eventfd2",
                "execve",
                "execveat",
                "exit",
                "exit_group",
                "faccessat",
                "fadvise64",
                "fadvise64_64",
                "fallocate",
                "fanotify_mark",
                "fchdir",
                "fchmod",
                "fchmodat",
                "fchown",
                "fchown32",
                "fchownat",
                "fcntl",
                "fcntl64",
                "fdatasync",
                "fgetxattr",
                "flistxattr",
                "flock",
                "fork",
                "fremovexattr",
                "fsetxattr",
                "fstat",
                "fstat64",
                "fstatat64",
                "fstatfs",
                "fstatfs64",
                "fsync",
                "ftruncate",
                "ftruncate64",
                "futex",
                "getcwd",
                "getdents",
                "getdents64",
                "getegid",
                "getegid32",
                "geteuid",
                "geteuid32",
                "getgid",
                "getgid32",
                "getgroups",
                "getgroups32",
                "getitimer",
                "getpeername",
                "getpgid",
                "getpgrp",
                "getpid",
                "getppid",
                "getpriority",
                "getrandom",
                "getresgid",
                "getresgid32",
                "getresuid",
                "getresuid32",
                "getrlimit",
                "get_robust_list",
                "getrusage",
                "getsid",
                "getsockname",
                "getsockopt",
                "get_thread_area",
                "gettid",
                "gettimeofday",
                "getuid",
                "getuid32",
                "getxattr",
                "inotify_add_watch",
                "inotify_init",
                "inotify_init1",
                "inotify_rm_watch",
                "io_cancel",
                "ioctl",
                "io_destroy",
                "io_getevents",
                "ioprio_get",
                "ioprio_set",
                "io_setup",
                "io_submit",
                "ipc",
                "kill",
                "lchown",
                "lchown32",
                "lgetxattr",
                "link",
                "linkat",
                "listen",
                "listxattr",
                "llistxattr",
                "_llseek",
                "lremovexattr",
                "lseek",
                "lsetxattr",
                "lstat",
                "lstat64",
                "madvise",
                "memfd_create",
                "mincore",
                "mkdir",
                "mkdirat",
                "mknod",
                "mknodat",
                "mlock",
                "mlock2",
                "mlockall",
                "mmap",
                "mmap2",
                "mprotect",
                "mq_getsetattr",
                "mq_notify",
                "mq_open",
                "mq_timedreceive",
                "mq_timedsend",
                "mq_unlink",
                "mremap",
                "msgctl",
                "msgget",
                "msgrcv",
                "msgsnd",
                "msync",
                "munlock",
                "munlockall",
                "munmap",
                "nanosleep",
                "newfstatat",
                "_newselect",
                "open",
                "openat",
                "pause",
                "pipe",
                "pipe2",
                "poll",
                "ppoll",
                "prctl",
                "pread64",
                "preadv",
                "preadv2",
                "prlimit64",
                "pselect6",
                "ptrace",
                "pwrite64",
                "pwritev",
                "pwritev2",
                "read",
                "readahead",
                "readlink",
                "readlinkat",
                "readv",
                "recv",
                "recvfrom",
                "recvmmsg",
                "recvmsg",
                "remap_file_pages",
                "removexattr",
                "rename",
                "renameat",
                "renameat2",
                "restart_syscall",
                "rmdir",
                "rt_sigaction",
                "rt_sigpending",
                "rt_sigprocmask",
                "rt_sigqueueinfo",
                "rt_sigreturn",
                "rt_sigsuspend",
                "rt_sigtimedwait",
                "rt_tgsigqueueinfo",
                "sched_getaffinity",
                "sched_getattr",
                "sched_getparam",
                "sched_get_priority_max",
                "sched_get_priority_min",
                "sched_getscheduler",
                "sched_rr_get_interval",
                "sched_setaffinity",
                "sched_setattr",
                "sched_setparam",
                "sched_setscheduler",
                "sched_yield",
                "seccomp",
                "select",
                "semctl",
                "semget",
                "semop",
                "semtimedop",
                "send",
                "sendfile",
                "sendfile64",
                "sendmmsg",
                "sendmsg",
                "sendto",
                "setfsgid",
                "setfsgid32",
                "setfsuid",
                "setfsuid32",
                "setgid",
                "setgid32",
                "setgroups",
                "setgroups32",
                "setitimer",
                "setpgid",
                "setpriority",
                "setregid",
                "setregid32",
                "setresgid",
                "setresgid32",
                "setresuid",
                "setresuid32",
                "setreuid",
                "setreuid32",
                "setrlimit",
                "set_robust_list",
                "setsid",
                "setsockopt",
                "set_thread_area",
                "set_tid_address",
                "setuid",
                "setuid32",
                "setxattr",
                "shmat",
                "shmctl",
                "shmdt",
                "shmget",
                "shutdown",
                "sigaltstack",
                "signalfd",
                "signalfd4",
                "sigreturn",
                "socket",
                "socketcall",
                "socketpair",
                "splice",
                "stat",
                "stat64",
                "statfs",
                "statfs64",
                "statx",
                "symlink",
                "symlinkat",
                "sync",
                "sync_file_range",
                "syncfs",
                "sysinfo",
                "syslog",
                "tee",
                "tgkill",
                "time",
                "timer_create",
                "timer_delete",
                "timerfd_create",
                "timerfd_gettime",
                "timerfd_settime",
                "timer_getoverrun",
                "timer_gettime",
                "timer_settime",
                "times",
                "tkill",
                "truncate",
                "truncate64",
                "ugetrlimit",
                "umask",
                "uname",
                "unlink",
                "unlinkat",
                "utime",
                "utimensat",
                "utimes",
                "vfork",
                "vmsplice",
                "wait4",
                "waitid",
                "waitpid",
                "write",
                "writev"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF

    success "Container security configured"
    update_container_state "security_configured" "true"
}

# Main installation function
install_container_runtime() {
    local runtime="${1:-docker}"

    log "Installing container runtime: $runtime"

    initialize_container_support
    load_config

    case $runtime in
        docker)
            install_docker
            if [[ "${INSTALL_DOCKER_COMPOSE:-true}" == "true" ]]; then
                install_docker_compose
            fi
            setup_container_networking
            setup_container_security
            ;;
        podman)
            install_podman
            ;;
        both)
            install_docker
            if [[ "${INSTALL_DOCKER_COMPOSE:-true}" == "true" ]]; then
                install_docker_compose
            fi
            install_podman
            setup_container_networking
            setup_container_security
            ;;
        *)
            error "Unknown runtime: $runtime"
            error "Supported runtimes: docker, podman, both"
            return 1
            ;;
    esac

    # Install optional services
    if [[ "${INSTALL_PORTAINER:-true}" == "true" ]] && [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        install_portainer
    fi

    if [[ "${ENABLE_WATCHTOWER:-true}" == "true" ]] && [[ "$runtime" == "docker" || "$runtime" == "both" ]]; then
        install_watchtower
    fi

    # Create sample services and management tools
    create_sample_services
    create_container_manager

    success "Container runtime installation completed: $runtime"
    log "Container runtime installation completed: $runtime"
}

# Show container status
show_container_status() {
    echo -e "${CYAN}🐳 Container Runtime Status${NC}"
    echo

    # Docker status
    if command -v docker >/dev/null 2>&1; then
        success "Docker: $(docker --version)"
        if systemctl is-active --quiet docker; then
            success "Docker service: Active"
        else
            error "Docker service: Inactive"
        fi

        # Show running containers
        local running_containers
        running_containers=$(docker ps --format "table {{.Names}}\t{{.Status}}" | tail -n +2)
        if [[ -n "$running_containers" ]]; then
            echo
            info "Running containers:"
            echo "$running_containers" | while read -r line; do
                success "$line"
            done
        fi
    else
        warning "Docker: Not installed"
    fi

    # Docker Compose status
    if command -v docker-compose >/dev/null 2>&1; then
        success "Docker Compose: $(docker-compose --version)"
    else
        warning "Docker Compose: Not installed"
    fi

    # Podman status
    if command -v podman >/dev/null 2>&1; then
        success "Podman: $(podman --version)"
    else
        warning "Podman: Not installed"
    fi

    echo
    info "Container services directory: $DOCKER_COMPOSE_DIR"
    info "Container data directory: $CONTAINER_DATA_DIR"
}

# Show help
show_help() {
    echo "Pi Gateway Container Support System"
    echo
    echo "Usage: $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "  install [runtime]    Install container runtime (docker, podman, both)"
    echo "  status               Show container runtime status"
    echo "  services             List available services"
    echo "  help                 Show this help message"
    echo
    echo "Options:"
    echo "  --dry-run           Show what would be done without making changes"
    echo "  --debug             Enable debug output"
    echo
    echo "Container Runtimes:"
    echo "  docker              Install Docker CE (default)"
    echo "  podman              Install Podman"
    echo "  both                Install both Docker and Podman"
    echo
    echo "Examples:"
    echo "  $(basename "$0") install docker"
    echo "  $(basename "$0") status"
    echo "  $(basename "$0") services"
    echo
}

# Main execution
main() {
    local command="${1:-}"

    # Handle global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            --debug)
                export DEBUG=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    case $command in
        install)
            local runtime="${2:-docker}"
            install_container_runtime "$runtime"
            ;;
        status)
            show_container_status
            ;;
        services)
            if [[ -f "$SCRIPT_DIR/container-manager.sh" ]]; then
                "$SCRIPT_DIR/container-manager.sh" list
            else
                warning "Container manager not installed"
                echo "Run '$(basename "$0") install' first"
            fi
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -n "$command" ]]; then
                error "Unknown command: $command"
            else
                error "No command specified"
            fi
            echo "Use '$(basename "$0") help' for available commands"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
