# Pi Gateway

A comprehensive homelab bootstrap script that transforms a Raspberry Pi 500 into a secure, self-hosted server for remote access and networking.

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

## Features

- **🔐 Secure Remote Access**: Encrypted VPN, hardened SSH, remote desktop
- **🌐 Dynamic IP Support**: Reliable external access via Dynamic DNS
- **⚡ One-Script Setup**: Fully automated deployment from fresh OS install
- **🔧 Extensible Platform**: Foundation for additional self-hosted services

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

## Development

```bash
# Set up development environment
make dev-setup

# Validate scripts
make validate

# Run tests
make test
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