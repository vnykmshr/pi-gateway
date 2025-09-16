# Pi Gateway Extension System

Guide for extending Pi Gateway with additional services and functionality.

## Table of Contents

1. [Extension Overview](#extension-overview)
2. [Creating Extensions](#creating-extensions)
3. [Extension Structure](#extension-structure)
4. [Integration Points](#integration-points)
5. [Example Extensions](#example-extensions)
6. [Best Practices](#best-practices)
7. [Testing Extensions](#testing-extensions)
8. [Contributing Extensions](#contributing-extensions)

## Extension Overview

Pi Gateway is designed with extensibility in mind. The extension system allows you to:

- Add new services and functionality
- Integrate custom applications
- Extend monitoring and management capabilities
- Create domain-specific configurations

### Extension Philosophy

Extensions should:
- ✅ **Integrate cleanly** with existing Pi Gateway infrastructure
- ✅ **Follow security best practices**
- ✅ **Include comprehensive testing**
- ✅ **Provide clear documentation**
- ✅ **Support dry-run mode**

## Extension Structure

### Directory Layout

```
extensions/
├── my-extension/
│   ├── README.md              # Extension documentation
│   ├── setup.sh               # Main setup script
│   ├── config/
│   │   ├── defaults.conf      # Default configuration
│   │   └── templates/         # Configuration templates
│   ├── scripts/
│   │   ├── install.sh         # Installation logic
│   │   ├── configure.sh       # Configuration logic
│   │   └── manage.sh          # Management utilities
│   ├── tests/
│   │   ├── test-install.bats  # Installation tests
│   │   └── test-config.bats   # Configuration tests
│   └── assets/
│       └── service-files/     # Systemd service files
```

### Required Files

#### `README.md`
```markdown
# Extension Name

Brief description of what this extension provides.

## Features
- Feature 1
- Feature 2

## Requirements
- System requirements
- Dependencies

## Configuration
- Configuration options
- Examples

## Usage
- How to use the extension
- Common operations
```

#### `setup.sh`
```bash
#!/bin/bash
#
# Extension Setup Script
# This script integrates with Pi Gateway's main setup process
#

set -euo pipefail

# Extension metadata
readonly EXTENSION_NAME="my-extension"
readonly EXTENSION_VERSION="1.0.0"
readonly EXTENSION_DESCRIPTION="Description of extension"

# Source Pi Gateway common functions
if [[ -f "$(dirname "$0")/../../scripts/common.sh" ]]; then
    source "$(dirname "$0")/../../scripts/common.sh"
fi

# Extension-specific setup logic
main() {
    header "Setting up $EXTENSION_NAME"

    # Check requirements
    check_requirements

    # Install dependencies
    install_dependencies

    # Configure service
    configure_service

    # Start and enable service
    enable_service

    success "$EXTENSION_NAME setup completed"
}

# Run main function
main "$@"
```

## Creating Extensions

### Step 1: Initialize Extension

```bash
# Create extension directory
mkdir -p extensions/my-extension/{config,scripts,tests,assets}

# Create basic structure
cd extensions/my-extension

# Create README
cat > README.md << 'EOF'
# My Extension

Description of your extension.

## Features
- List key features

## Requirements
- Dependencies
- System requirements

## Configuration
- Configuration details
EOF
```

### Step 2: Implement Setup Script

```bash
cat > setup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

readonly EXTENSION_NAME="my-extension"
readonly SERVICE_NAME="my-service"

# Include Pi Gateway utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_GATEWAY_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [[ -f "$PI_GATEWAY_ROOT/scripts/common.sh" ]]; then
    source "$PI_GATEWAY_ROOT/scripts/common.sh"
else
    # Fallback logging functions
    success() { echo "✓ $1"; }
    error() { echo "✗ $1"; }
    info() { echo "ℹ $1"; }
fi

check_requirements() {
    info "Checking requirements for $EXTENSION_NAME"

    # Check if running as root when needed
    if [[ $EUID -ne 0 ]] && [[ "${ALLOW_NON_ROOT:-false}" != "true" ]]; then
        error "This extension requires root privileges"
        exit 1
    fi

    # Check dependencies
    for cmd in required-command-1 required-command-2; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done

    success "Requirements check passed"
}

install_dependencies() {
    info "Installing dependencies"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would install package-name"
        return
    fi

    if command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y package-name
    else
        error "Package manager not supported"
        exit 1
    fi

    success "Dependencies installed"
}

configure_service() {
    info "Configuring $SERVICE_NAME"

    local config_file="/etc/$SERVICE_NAME.conf"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would create configuration at $config_file"
        return
    fi

    # Create configuration from template
    cp "$SCRIPT_DIR/config/defaults.conf" "$config_file"

    # Set appropriate permissions
    chmod 644 "$config_file"

    success "Service configured"
}

enable_service() {
    info "Enabling $SERVICE_NAME"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would enable and start $SERVICE_NAME"
        return
    fi

    # Copy service file
    cp "$SCRIPT_DIR/assets/service-files/$SERVICE_NAME.service" \
       "/etc/systemd/system/"

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    success "$SERVICE_NAME enabled and started"
}

main() {
    header "Setting up $EXTENSION_NAME"

    check_requirements
    install_dependencies
    configure_service
    enable_service

    success "$EXTENSION_NAME setup completed successfully"
}

main "$@"
EOF

chmod +x setup.sh
```

### Step 3: Create Configuration

```bash
# Create default configuration
cat > config/defaults.conf << 'EOF'
# My Extension Configuration
# Customize these settings for your environment

# Service settings
ENABLE_SERVICE=true
SERVICE_PORT=8080
SERVICE_USER=pi

# Feature flags
ENABLE_LOGGING=true
LOG_LEVEL=info

# Network settings
BIND_ADDRESS=0.0.0.0
ALLOWED_NETWORKS="192.168.1.0/24,10.13.13.0/24"
EOF
```

### Step 4: Add Systemd Service

```bash
mkdir -p assets/service-files

cat > assets/service-files/my-service.service << 'EOF'
[Unit]
Description=My Extension Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=pi
Group=pi
ExecStart=/usr/local/bin/my-service
Restart=always
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/my-service

[Install]
WantedBy=multi-user.target
EOF
```

## Integration Points

### Pi Gateway Integration

#### Automatic Discovery

Pi Gateway automatically discovers extensions in the `extensions/` directory. To integrate:

1. **Place in extensions directory**: `extensions/my-extension/`
2. **Implement standard interface**: `setup.sh` with required functions
3. **Follow naming conventions**: Use consistent naming patterns

#### Configuration Integration

Extensions can integrate with Pi Gateway's configuration system:

```bash
# In your setup.sh, source Pi Gateway config
if [[ -f "$PI_GATEWAY_ROOT/config/setup.conf" ]]; then
    source "$PI_GATEWAY_ROOT/config/setup.conf"
fi

# Use Pi Gateway variables
if [[ "$ENABLE_MY_EXTENSION" == "true" ]]; then
    # Extension setup logic
fi
```

#### Service Management

Integrate with Pi Gateway's service management:

```bash
# Add to service status checks
echo "my-service" >> "$PI_GATEWAY_ROOT/config/managed-services.list"

# Integrate with backup system
echo "/etc/my-service.conf" >> "$PI_GATEWAY_ROOT/config/backup-files.list"
```

### CLI Integration

Extend the Pi Gateway CLI with custom commands:

```bash
# Create CLI extension
cat > scripts/cli-commands.sh << 'EOF'
#!/bin/bash

# Custom CLI commands for my-extension
cmd_my_extension() {
    local action="${1:-status}"

    case $action in
        status)
            systemctl status my-service
            ;;
        restart)
            sudo systemctl restart my-service
            ;;
        logs)
            journalctl -u my-service -f
            ;;
        *)
            echo "Usage: my-extension {status|restart|logs}"
            ;;
    esac
}
EOF
```

## Example Extensions

### Example 1: Web Dashboard Extension

```bash
# extensions/web-dashboard/setup.sh
#!/bin/bash
set -euo pipefail

readonly EXTENSION_NAME="web-dashboard"
readonly SERVICE_NAME="pi-gateway-dashboard"
readonly SERVICE_PORT="3000"

install_dependencies() {
    info "Installing Node.js and npm"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would install Node.js"
        return
    fi

    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    apt install -y nodejs

    success "Node.js installed"
}

setup_dashboard() {
    local app_dir="/opt/pi-gateway-dashboard"

    info "Setting up dashboard application"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would setup dashboard in $app_dir"
        return
    fi

    # Create application directory
    mkdir -p "$app_dir"
    cp -r "$SCRIPT_DIR/src/"* "$app_dir/"

    # Install dependencies
    cd "$app_dir"
    npm install --production

    # Set permissions
    chown -R pi:pi "$app_dir"

    success "Dashboard application ready"
}

configure_firewall() {
    info "Configuring firewall for dashboard"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would allow port $SERVICE_PORT"
        return
    fi

    ufw allow "$SERVICE_PORT"/tcp

    success "Firewall configured"
}

main() {
    header "Setting up $EXTENSION_NAME"

    check_requirements
    install_dependencies
    setup_dashboard
    configure_firewall
    create_service
    enable_service

    success "$EXTENSION_NAME available at http://$(hostname):$SERVICE_PORT"
}

main "$@"
```

### Example 2: Monitoring Extension

```bash
# extensions/monitoring/setup.sh
#!/bin/bash
set -euo pipefail

readonly EXTENSION_NAME="monitoring"

install_monitoring_tools() {
    info "Installing monitoring tools"

    local packages="htop iotop nethogs"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would install $packages"
        return
    fi

    apt update
    apt install -y $packages

    success "Monitoring tools installed"
}

setup_health_checks() {
    info "Setting up health check scripts"

    local cron_file="/etc/cron.d/pi-gateway-health"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would create health check cron job"
        return
    fi

    cat > "$cron_file" << 'EOF'
# Pi Gateway Health Checks
*/5 * * * * pi /opt/pi-gateway/extensions/monitoring/scripts/health-check.sh
EOF

    success "Health checks configured"
}

main() {
    header "Setting up $EXTENSION_NAME"

    install_monitoring_tools
    setup_health_checks

    success "Monitoring extension ready"
}

main "$@"
```

## Best Practices

### Security Guidelines

1. **Principle of Least Privilege**
   ```bash
   # Create dedicated users for services
   useradd -r -s /bin/false -d /var/lib/my-service my-service

   # Use appropriate file permissions
   chmod 600 /etc/my-service/secret.conf
   chown my-service:my-service /etc/my-service/secret.conf
   ```

2. **Input Validation**
   ```bash
   validate_input() {
       local input="$1"

       # Validate against expected pattern
       if [[ ! "$input" =~ ^[a-zA-Z0-9._-]+$ ]]; then
           error "Invalid input format"
           return 1
       fi
   }
   ```

3. **Secure Defaults**
   ```bash
   # Use secure default configurations
   DEFAULT_BIND_ADDRESS="127.0.0.1"  # Not 0.0.0.0
   DEFAULT_ENABLE_AUTH=true
   DEFAULT_LOG_LEVEL="warn"           # Not debug
   ```

### Code Quality

1. **Error Handling**
   ```bash
   set -euo pipefail  # Strict error handling

   # Check command success
   if ! command -v required-tool >/dev/null 2>&1; then
       error "Required tool not found"
       exit 1
   fi
   ```

2. **Dry-Run Support**
   ```bash
   if [[ "${DRY_RUN:-false}" == "true" ]]; then
       info "DRY-RUN: Would perform action"
       return 0
   fi

   # Actual action
   perform_action
   ```

3. **Logging and Feedback**
   ```bash
   # Use consistent logging
   info "Starting configuration..."
   success "Configuration completed"
   warning "Optional feature not available"
   error "Critical error occurred"
   ```

### Documentation Standards

1. **Clear README**: Include purpose, requirements, configuration, and usage
2. **Inline Comments**: Explain complex logic and configuration options
3. **Examples**: Provide working examples for common use cases
4. **Troubleshooting**: Document common issues and solutions

## Testing Extensions

### Unit Testing with BATS

```bash
# tests/test-install.bats
#!/usr/bin/env bats

load '../../../tests/test_helper/bats-support/load'
load '../../../tests/test_helper/bats-assert/load'

setup() {
    export DRY_RUN=true
    export MOCK_SYSTEM=true
}

@test "extension setup runs without errors" {
    run ./setup.sh
    assert_success
}

@test "dependencies are checked correctly" {
    run ./scripts/install.sh
    assert_output --partial "Checking requirements"
}

@test "service configuration is created" {
    run ./scripts/configure.sh
    assert_output --partial "Service configured"
}
```

### Integration Testing

```bash
# tests/test-integration.bats
#!/usr/bin/env bats

@test "service starts successfully" {
    systemctl start my-service
    run systemctl is-active my-service
    assert_output "active"
}

@test "service responds to requests" {
    run curl -s http://localhost:8080/health
    assert_success
    assert_output --partial "healthy"
}

@test "firewall rules are applied" {
    run ufw status
    assert_output --partial "8080/tcp"
}
```

### Testing Commands

```bash
# Run extension tests
make test-extension EXTENSION=my-extension

# Run all extension tests
make test-extensions

# Integration test with Pi Gateway
make test-all-integration
```

## Contributing Extensions

### Submission Guidelines

1. **Fork Repository**: Create a fork of the Pi Gateway repository
2. **Create Extension**: Develop your extension following the guidelines
3. **Test Thoroughly**: Ensure all tests pass
4. **Document Completely**: Include comprehensive documentation
5. **Submit PR**: Create a pull request with detailed description

### Review Criteria

Extensions are reviewed for:

- ✅ **Security**: No security vulnerabilities or bad practices
- ✅ **Quality**: Clean, well-structured code
- ✅ **Testing**: Comprehensive test coverage
- ✅ **Documentation**: Clear and complete documentation
- ✅ **Integration**: Proper integration with Pi Gateway
- ✅ **Usefulness**: Adds value to the Pi Gateway ecosystem

### Community Extensions

Popular community extensions:

- **Pi-hole Integration**: DNS-based ad blocking
- **Home Assistant**: Home automation platform
- **Nextcloud**: Self-hosted cloud storage
- **Plex Media Server**: Media streaming
- **GitLab Runner**: CI/CD automation
- **Prometheus Monitoring**: Advanced metrics collection

---

**Getting Started**:
1. Review [example extensions](#example-extensions)
2. Create your extension following the [structure guidelines](#extension-structure)
3. Test thoroughly using the [testing framework](#testing-extensions)
4. Submit for community review

**Previous**: [Troubleshooting](troubleshooting.md) | **Back**: [README](../README.md)