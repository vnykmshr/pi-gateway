# Pi Gateway Quick Start Guide

Get your Pi Gateway up and running in 15 minutes with this streamlined setup process.

## Prerequisites

- Raspberry Pi 4 (4GB+ RAM recommended)
- 32GB+ MicroSD card with Raspberry Pi OS
- Ethernet connection
- SSH access enabled

## 1. Quick Installation

```bash
# Clone and setup in one command
curl -sSL https://raw.githubusercontent.com/vnykmshr/pi-gateway/main/scripts/quick-install.sh | bash
```

Or manual installation:

```bash
# Clone repository
git clone https://github.com/vnykmshr/pi-gateway.git
cd pi-gateway

# Check requirements
make check

# Run complete setup
make setup
```

## 2. Essential Configuration

### Setup SSH Keys (Recommended)

```bash
# On your local machine, generate SSH key
ssh-keygen -t ed25519 -f ~/.ssh/pi-gateway

# Copy to Pi
ssh-copy-id -i ~/.ssh/pi-gateway.pub pi@your-pi-ip

# Test key-based login
ssh -i ~/.ssh/pi-gateway pi@your-pi-ip
```

### Configure VPN Access

```bash
# Add your first VPN client
./scripts/vpn-client-manager.sh add my-laptop

# Show QR code for mobile setup
./scripts/vpn-client-manager.sh show my-phone
```

## 3. Verify Installation

```bash
# Check system status
./scripts/pi-gateway-cli.sh status

# Test all services
./scripts/service-status.sh

# View system info
./scripts/pi-gateway-cli.sh info
```

## 4. Access Your Services

- **SSH**: `ssh pi@your-pi-ip`
- **VPN**: Use generated WireGuard configuration
- **Web Management**: `http://your-pi-ip:9000` (Portainer)
- **Monitoring**: `http://your-pi-ip:3000` (Grafana)

## 5. Next Steps

### Enable Additional Services

```bash
# Install container platform
./scripts/container-support.sh install docker

# Start monitoring stack
./scripts/container-manager.sh start monitoring

# Setup automated maintenance
./scripts/auto-maintenance.sh configure
```

### Security Hardening

```bash
# Apply security hardening
./scripts/security-hardening.sh harden

# Enable monitoring
./scripts/monitoring-system.sh setup

# Configure backups
./scripts/backup-config.sh setup
```

## Common Commands

| Task | Command |
|------|---------|
| System status | `./scripts/pi-gateway-cli.sh status` |
| Add VPN client | `./scripts/vpn-client-manager.sh add <name>` |
| Start service | `./scripts/container-manager.sh start <service>` |
| Create backup | `./scripts/backup-config.sh create quick-backup` |
| Check security | `./scripts/security-hardening.sh status` |
| View logs | `./scripts/monitoring-system.sh logs` |

## Troubleshooting

### Can't connect via SSH?
```bash
# Check if SSH is running
sudo systemctl status ssh

# Check firewall
sudo ufw status
```

### VPN not working?
```bash
# Check WireGuard status
sudo wg show

# Restart VPN service
sudo systemctl restart wg-quick@wg0
```

### Need help?
- Check [Troubleshooting Guide](troubleshooting.md)
- View [Full Documentation](../README.md)
- Report issues on [GitHub](https://github.com/vnykmshr/pi-gateway/issues)

---

**🎉 Your Pi Gateway is ready!** For advanced configuration, see the [Complete Setup Guide](setup-guide.md).