# Pi Gateway Setup Guide

Complete installation and configuration guide for Pi Gateway homelab bootstrap system.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Hardware Setup](#hardware-setup)
3. [Initial Pi Configuration](#initial-pi-configuration)
4. [Installing Pi Gateway](#installing-pi-gateway)
5. [Configuration Options](#configuration-options)
6. [First Run Setup](#first-run-setup)
7. [Post-Installation](#post-installation)
8. [Verification](#verification)

## Prerequisites

### Hardware Requirements

- **Raspberry Pi**: Pi 4 or Pi 5 recommended (Pi 3 supported with limited performance)
- **Storage**: 32GB+ MicroSD card (Class 10 or better) or USB SSD
- **Network**: Ethernet connection recommended for initial setup
- **Power**: Official Raspberry Pi power supply
- **Optional**: Case with adequate cooling

### Software Requirements

- **Raspberry Pi OS**: Lite or Desktop version (latest)
- **Network Access**: Internet connection for package downloads
- **Router Access**: Administrative access to configure port forwarding
- **SSH Client**: For remote access (PuTTY, Terminal, etc.)

### Network Prerequisites

- **Static/Reserved IP**: Configure your router to assign a consistent IP to your Pi
- **Port Forwarding**: Access to router settings for VPN and remote access setup
- **Dynamic DNS**: Account with DuckDNS, No-IP, or Cloudflare (optional but recommended)

## Hardware Setup

### 1. Prepare the MicroSD Card

```bash
# Download Raspberry Pi Imager
# https://www.raspberrypi.org/software/

# Flash Raspberry Pi OS Lite (recommended for headless setup)
# Enable SSH in advanced options
# Set username/password
# Configure WiFi if needed
```

### 2. Initial Boot

1. Insert MicroSD card into Pi
2. Connect ethernet cable (recommended for setup)
3. Connect power supply
4. Wait 2-3 minutes for first boot

### 3. Find Your Pi's IP Address

```bash
# Method 1: Check router admin panel
# Look for "raspberrypi" in connected devices

# Method 2: Network scan (from your computer)
nmap -sn 192.168.1.0/24

# Method 3: Use Pi Finder tools
# Download from Raspberry Pi website
```

## Initial Pi Configuration

### 1. SSH Connection

```bash
# Replace with your Pi's IP address
ssh pi@192.168.1.100

# Or if using custom username
ssh your-username@192.168.1.100
```

### 2. Basic System Update

```bash
# Update package lists and system
sudo apt update && sudo apt upgrade -y

# Reboot if kernel was updated
sudo reboot
```

### 3. Raspberry Pi Configuration

```bash
# Open configuration tool
sudo raspi-config

# Recommended settings:
# 1. Change User Password (if not done during imaging)
# 2. Network Options > Hostname (optional)
# 3. Interfacing Options > SSH (ensure enabled)
# 4. Advanced Options > Memory Split > 16 (for headless)
# 5. Finish and reboot
```

## Installing Pi Gateway

### 1. Clone Repository

```bash
# Clone the Pi Gateway repository
git clone https://github.com/vnykmshr/pi-gateway.git
cd pi-gateway

# Make scripts executable (if needed)
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### 2. System Requirements Check

```bash
# Check if your system meets requirements
make check

# This will verify:
# - Hardware compatibility
# - Required packages
# - Network connectivity
# - Permissions
```

### 3. Review Configuration

```bash
# Copy configuration template
cp config/setup.conf.template config/setup.conf

# Edit configuration (optional)
nano config/setup.conf
```

## Configuration Options

### Basic Configuration

Edit `config/setup.conf` to customize your installation:

```bash
# Core Components
ENABLE_SSH=true                    # SSH hardening and security
ENABLE_VPN=true                    # WireGuard VPN server
ENABLE_FIREWALL=true               # UFW firewall configuration
ENABLE_REMOTE_DESKTOP=false        # VNC/RDP (set true if needed)
ENABLE_DDNS=true                   # Dynamic DNS (recommended)

# Network Settings
SSH_PORT=2222                      # Custom SSH port
VPN_PORT=51820                     # WireGuard port
VPN_NETWORK="10.13.13.0/24"        # VPN network range
```

### Advanced Configuration

```bash
# Security Settings
FAIL2BAN_ENABLED=true              # Intrusion detection
FAIL2BAN_BAN_TIME=3600             # Ban duration (1 hour)
FAIL2BAN_MAX_RETRY=3               # Failed attempts before ban

# Dynamic DNS Configuration
DDNS_PROVIDER="duckdns"            # Provider choice
DDNS_HOSTNAME="your-domain"        # Your hostname
DDNS_TOKEN="your-token"            # Provider API token
```

### Dynamic DNS Setup

#### DuckDNS (Recommended)

1. Visit [DuckDNS.org](https://www.duckdns.org)
2. Create account and domain (e.g., `myhome.duckdns.org`)
3. Copy your token
4. Update configuration:

```bash
DDNS_PROVIDER="duckdns"
DUCKDNS_DOMAIN="myhome.duckdns.org"
DUCKDNS_TOKEN="your-token-here"
```

#### Cloudflare

```bash
DDNS_PROVIDER="cloudflare"
CLOUDFLARE_EMAIL="your@email.com"
CLOUDFLARE_API_KEY="your-api-key"
CLOUDFLARE_DOMAIN="yourdomain.com"
```

## First Run Setup

### 1. Interactive Setup (Recommended)

```bash
# Run interactive setup
make setup

# Follow prompts for:
# 1. Installation mode selection
# 2. Component configuration
# 3. Network settings
# 4. Security preferences
```

### 2. Non-Interactive Setup

```bash
# For automated/scripted installation
./setup.sh --non-interactive

# With dry-run for testing
./setup.sh --dry-run --non-interactive
```

### 3. Custom Component Setup

```bash
# Install only specific components
./setup.sh --components ssh,vpn,firewall
```

## Post-Installation

### 1. Router Configuration

#### Port Forwarding

Configure your router to forward these ports to your Pi:

- **SSH**: External port → Pi IP:2222
- **VPN**: External port → Pi IP:51820
- **VNC**: External port → Pi IP:5900 (if enabled)

Example router configuration:
```
Service: SSH
External Port: 2222
Internal IP: 192.168.1.100
Internal Port: 2222
Protocol: TCP

Service: WireGuard VPN
External Port: 51820
Internal IP: 192.168.1.100
Internal Port: 51820
Protocol: UDP
```

### 2. Generate VPN Client Configurations

```bash
# Generate client configuration for your devices
sudo /opt/pi-gateway/scripts/generate-vpn-client.sh client-laptop
sudo /opt/pi-gateway/scripts/generate-vpn-client.sh client-phone

# Configurations saved to: /etc/wireguard/clients/
```

### 3. SSH Key Setup

```bash
# Copy your public key to the Pi (from your computer)
ssh-copy-id pi@your-pi-ip

# Or manually add your key
mkdir -p ~/.ssh
echo "your-public-key-content" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

## Verification

### 1. Service Status Check

```bash
# Check all Pi Gateway services
make status

# Or use the detailed status script
./scripts/service-status.sh
```

### 2. Network Connectivity

```bash
# Test internal connectivity
ping 10.13.13.1  # VPN gateway

# Test external access (from another network)
ssh -p 2222 pi@your-ddns-hostname.duckdns.org
```

### 3. VPN Testing

```bash
# Import client configuration to your device
# Test VPN connection
# Verify you can access internal network (192.168.1.x)
# Check your external IP shows as your home IP
```

### 4. Security Verification

```bash
# Check firewall status
sudo ufw status verbose

# Review fail2ban logs
sudo fail2ban-client status sshd

# Verify SSH key authentication
sudo grep "PasswordAuthentication" /etc/ssh/sshd_config
```

## Common Setup Issues

### Permission Errors

```bash
# If setup fails with permission errors
sudo usermod -aG sudo $USER
newgrp sudo

# Logout and login again
```

### Network Issues

```bash
# If unable to reach external network
ping 8.8.8.8

# Check DNS resolution
nslookup google.com

# Verify network interface
ip addr show
```

### Port Conflicts

```bash
# If ports are already in use
sudo netstat -tulpn | grep :22
sudo netstat -tulpn | grep :51820

# Kill conflicting processes if necessary
sudo systemctl stop service-name
```

## Next Steps

After successful installation:

1. **Test Services**: Verify all components work correctly
2. **Configure Devices**: Set up VPN clients on your devices
3. **Monitor System**: Use `make status` regularly
4. **Backup Configuration**: Use `make backup-config`
5. **Read Usage Guide**: See [usage.md](usage.md) for daily operations

## Getting Help

- **Status Check**: `./scripts/service-status.sh`
- **Logs**: `make logs`
- **Troubleshooting**: See [troubleshooting.md](troubleshooting.md)
- **Issues**: [GitHub Issues](https://github.com/vnykmshr/pi-gateway/issues)

---

**Next**: [Usage Guide](usage.md) | **Back**: [README](../README.md)