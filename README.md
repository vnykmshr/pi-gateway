# Pi Gateway - Homelab Bootstrap

[![CI Status](https://github.com/vnykmshr/pi-gateway/workflows/Pi%20Gateway%20CI/badge.svg)](https://github.com/vnykmshr/pi-gateway/actions)
[![Release](https://img.shields.io/github/v/release/vnykmshr/pi-gateway)](https://github.com/vnykmshr/pi-gateway/releases)
[![License](https://img.shields.io/github/license/vnykmshr/pi-gateway)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-40%20tests%20|%2092.5%25%20pass-green)](https://github.com/vnykmshr/pi-gateway/actions)

**Complete Raspberry Pi homelab bootstrap system with automated security hardening, VPN setup, and comprehensive testing infrastructure.**

## Overview

Pi Gateway provides a one-script automated setup for core services while supporting dynamic IP environments. All provisioning is tracked in this repository, following Infrastructure as Code (IaC) principles for reliability, reproducibility, and extensibility.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/vnykmshr/pi-gateway.git
cd pi-gateway

# Check system requirements
make check

# Run the setup (on your Raspberry Pi)
make setup
```

## ✨ Features

### 🔐 **Security & Hardening**
- **SSH Hardening**: Key-based authentication, fail2ban, custom ports
- **System Hardening**: Kernel parameters, network security, service management
- **Firewall Configuration**: UFW setup with secure defaults
- **User Account Security**: Service accounts, permission hardening

### 🌐 **VPN & Remote Access**
- **WireGuard VPN Server**: Automated setup with client management
- **Dynamic DNS**: Cloudflare integration for remote access
- **Remote Desktop**: VNC server configuration
- **Port Management**: Automated port forwarding setup

### 🧪 **Development & Testing**
- **Virtual Sandbox**: Complete dry-run environment with hardware mocking
- **QEMU Integration**: Full Raspberry Pi emulation for testing
- **Docker Testing**: Cross-platform development containers (simple + systemd modes)
- **40+ Unit Tests**: Comprehensive test coverage (92.5% pass rate)

### 🏠 **Homelab Ready**
- **Service Discovery**: mDNS and local network integration
- **Monitoring Setup**: System health monitoring
- **Extension Support**: Plugin architecture for custom services

## Requirements

### Hardware
- Raspberry Pi 500 (or compatible Pi 4/5)
- Raspberry Pi OS (Lite or Desktop)
- 32GB+ MicroSD card
- Reliable power supply & network connection

### Software
- Administrator access to home router
- Dynamic DNS provider account (DuckDNS, No-IP, etc.)
- SSH client for initial access

## Core Services

- **System Hardening**: Security best practices for internet-connected devices
- **SSH Access**: Key-based authentication, password login disabled
- **WireGuard VPN**: High-performance encrypted remote connectivity
- **Remote Desktop**: GUI access via VNC or xRDP
- **Dynamic DNS**: Reliable hostname for changing IPs

## Documentation

- [Setup Guide](docs/setup-guide.md) - Detailed installation instructions
- [Usage Guide](docs/usage.md) - How to use installed services
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions

## Project Structure

```
pi-gateway/
├── setup.sh                      # Master setup script
├── scripts/                      # Modular service scripts
├── config/                       # Configuration templates
├── docs/                         # Documentation
├── extensions/                   # Optional future services
└── tests/                       # Validation scripts
```

## 🧪 Development & Testing

### Testing Environment
```bash
# Quick dry-run tests (safe, no system changes)
make test-dry-run

# Complete unit test suite
make test-unit

# Docker integration testing
make test-docker              # Simple mode
make test-docker-systemd      # Systemd mode

# Full test suite
make test-all-integration
```

### Development Setup
```bash
# Set up development environment
make dev-setup

# Code quality checks
make lint
make format-check

# QEMU testing (hardware emulation)
make setup-qemu
make test-integration
```

### Available Testing Commands
```bash
make test-dry-run           # Safe dry-run testing
make test-unit              # BATS unit tests
make test-docker            # Docker integration tests
make test-all-integration   # Complete test suite
make docker-shell          # Interactive Docker container
make docker-cleanup         # Clean Docker environment
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `make test` and `make validate`
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

For issues and feature requests, please visit the [GitHub Issues](https://github.com/vnykmshr/pi-gateway/issues) page.