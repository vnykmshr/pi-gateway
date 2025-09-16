# Pi Gateway Deployment Guide

A comprehensive guide for deploying Pi Gateway in production environments.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Hardware Setup](#hardware-setup)
- [Initial Installation](#initial-installation)
- [Configuration Management](#configuration-management)
- [Security Deployment](#security-deployment)
- [Production Hardening](#production-hardening)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Backup & Recovery](#backup--recovery)
- [Network Configuration](#network-configuration)
- [Container Services](#container-services)
- [Troubleshooting](#troubleshooting)

## Pre-Deployment Checklist

### Hardware Requirements

✅ **Minimum Specifications**
- Raspberry Pi 4 Model B (4GB RAM minimum, 8GB recommended)
- 64GB+ MicroSD card (Class 10 or better)
- Reliable power supply (3.5A USB-C)
- Ethernet connection for initial setup
- Internet connectivity

✅ **Network Requirements**
- Static IP assignment or DHCP reservation
- Router admin access for port forwarding
- DNS provider account (for DDNS)
- Firewall configuration access

✅ **Accounts & Credentials**
- SSH key pair generated
- Dynamic DNS account setup
- Email account for notifications
- Cloud backup storage (optional)

## Hardware Setup

### 1. Raspberry Pi Preparation

```bash
# Flash Raspberry Pi OS Lite to SD card
# Enable SSH before first boot
touch /Volumes/boot/ssh

# Configure WiFi (if needed)
cat > /Volumes/boot/wpa_supplicant.conf << EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="YourNetworkName"
    psk="YourPassword"
    key_mgmt=WPA-PSK
}
EOF
```

### 2. Initial Boot Configuration

```bash
# SSH into the Pi (default credentials: pi/raspberry)
ssh pi@raspberrypi.local

# Update system
sudo apt update && sudo apt upgrade -y

# Change default password
passwd

# Configure locale and timezone
sudo raspi-config
```

## Initial Installation

### 1. Clone Pi Gateway

```bash
# Clone the repository
git clone https://github.com/vnykmshr/pi-gateway.git
cd pi-gateway

# Check system requirements
make check
```

### 2. Quick Start Installation

```bash
# Run complete setup
make setup

# Alternative: Step-by-step setup
./scripts/check-requirements.sh
./scripts/install-dependencies.sh
./scripts/system-hardening.sh
./scripts/ssh-setup.sh
./scripts/firewall-setup.sh
./scripts/vpn-setup.sh
```

### 3. Verify Installation

```bash
# Check system status
./scripts/pi-gateway-cli.sh status

# Verify services
./scripts/service-status.sh

# Test VPN connectivity
./scripts/vpn-client-manager.sh add test-device
```

## Configuration Management

### 1. Environment Configuration

Create production configuration:

```bash
# Edit main configuration
sudo nano /etc/pi-gateway/config.conf

# Key settings to configure:
ENVIRONMENT="production"
ENABLE_MONITORING=true
ENABLE_AUTO_UPDATES=true
BACKUP_ENABLED=true
NOTIFICATION_EMAIL="admin@yourdomain.com"
```

### 2. Network Configuration

```bash
# Configure static IP
sudo nano /etc/dhcpcd.conf

# Add:
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=1.1.1.1 8.8.8.8
```

### 3. Dynamic DNS Setup

```bash
# Configure DDNS
./scripts/ddns-setup.sh

# Follow prompts for your provider:
# - DuckDNS: Enter domain and token
# - No-IP: Enter username and password
# - Cloudflare: Enter API key and zone
```

## Security Deployment

### 1. SSH Hardening

```bash
# Apply SSH security settings
./scripts/ssh-setup.sh

# Copy your public key
ssh-copy-id -i ~/.ssh/id_rsa.pub pi@your-pi-ip

# Verify key-based login works
ssh -i ~/.ssh/id_rsa pi@your-pi-ip

# Disable password authentication
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

### 2. Firewall Configuration

```bash
# Configure UFW firewall
./scripts/firewall-setup.sh

# Verify firewall status
sudo ufw status verbose

# Common ports to allow:
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 51820/udp  # WireGuard VPN
sudo ufw allow 80/tcp     # HTTP (if needed)
sudo ufw allow 443/tcp    # HTTPS (if needed)
```

### 3. Security Hardening

```bash
# Apply comprehensive security hardening
./scripts/security-hardening.sh harden

# Run compliance checks
./scripts/security-hardening.sh check

# Generate security report
./scripts/security-hardening.sh report
```

## Production Hardening

### 1. System Optimization

```bash
# Apply system hardening
./scripts/system-hardening.sh

# Enable automatic updates
./scripts/auto-maintenance.sh configure

# Optimize network performance
./scripts/network-optimizer.sh optimize --profile production
```

### 2. Monitoring Setup

```bash
# Configure monitoring system
./scripts/monitoring-system.sh setup

# Start monitoring daemon
./scripts/monitoring-system.sh monitor --daemon

# Configure alerts
./scripts/monitoring-system.sh alert --email admin@domain.com
```

### 3. Backup Configuration

```bash
# Setup automated backups
./scripts/backup-config.sh setup

# Create initial backup
./scripts/backup-config.sh create production-initial

# Schedule automatic backups
./scripts/auto-maintenance.sh schedule
```

## Network Configuration

### 1. Router Port Forwarding

Configure your router to forward these ports to your Pi:

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| SSH | 22 | TCP | Remote administration |
| WireGuard | 51820 | UDP | VPN access |
| HTTP | 80 | TCP | Web services (optional) |
| HTTPS | 443 | TCP | Secure web services (optional) |

### 2. VPN Setup

```bash
# Setup WireGuard VPN server
./scripts/vpn-setup.sh

# Create client configurations
./scripts/vpn-client-manager.sh add laptop
./scripts/vpn-client-manager.sh add phone
./scripts/vpn-client-manager.sh add tablet

# Show client configuration and QR code
./scripts/vpn-client-manager.sh show phone
```

### 3. DNS Configuration

```bash
# Configure local DNS resolution
echo "192.168.1.100 pi-gateway.local" | sudo tee -a /etc/hosts

# Setup Pi-hole (optional)
./scripts/container-support.sh install docker
./scripts/container-manager.sh start pihole
```

## Container Services

### 1. Docker Setup

```bash
# Install container runtime
./scripts/container-support.sh install docker

# Verify installation
docker --version
docker-compose --version

# Start Portainer for web management
docker ps | grep portainer
```

### 2. Common Services

```bash
# Home Assistant
cd containers/homeassistant
docker-compose up -d

# Monitoring Stack (Grafana + InfluxDB)
cd containers/monitoring
docker-compose up -d

# Node-RED
cd containers/nodered
docker-compose up -d

# Pi-hole DNS
cd containers/pihole
docker-compose up -d
```

### 3. Service Management

```bash
# List available services
./scripts/container-manager.sh list

# Start/stop services
./scripts/container-manager.sh start homeassistant
./scripts/container-manager.sh stop pihole

# View logs
./scripts/container-manager.sh logs grafana

# Check status
./scripts/container-manager.sh status nodered
```

## Monitoring & Maintenance

### 1. System Monitoring

```bash
# Real-time system monitoring
./scripts/monitoring-system.sh status

# Generate performance report
./scripts/monitoring-system.sh report

# Check service health
./scripts/service-status.sh
```

### 2. Automated Maintenance

```bash
# Configure maintenance schedule
./scripts/auto-maintenance.sh configure

# Manual maintenance run
./scripts/auto-maintenance.sh run

# Check maintenance logs
tail -f /var/log/pi-gateway/auto-maintenance.log
```

### 3. Performance Optimization

```bash
# Network optimization
./scripts/network-optimizer.sh optimize

# System performance tuning
./scripts/auto-maintenance.sh optimize

# Monitor resource usage
./scripts/monitoring-system.sh metrics
```

## Backup & Recovery

### 1. Configuration Backup

```bash
# Create full system backup
./scripts/backup-config.sh create full-backup

# List available backups
./scripts/backup-config.sh list

# Restore from backup
./scripts/backup-config.sh restore backup-name
```

### 2. Container Data Backup

```bash
# Backup container volumes
./scripts/auto-maintenance.sh backup

# Schedule regular backups
crontab -e
# Add: 0 2 * * * /home/pi/pi-gateway/scripts/auto-maintenance.sh backup
```

### 3. Disaster Recovery

```bash
# Emergency restoration procedure
# 1. Fresh Pi OS installation
# 2. Clone Pi Gateway repository
# 3. Restore from backup

git clone https://github.com/vnykmshr/pi-gateway.git
cd pi-gateway
./scripts/backup-config.sh restore emergency-backup
./scripts/auto-maintenance.sh verify
```

## Security Best Practices

### 1. Regular Security Updates

```bash
# Enable automatic security updates
./scripts/auto-maintenance.sh configure --security-updates

# Manual security update
sudo apt update && sudo apt upgrade -y

# Update Pi Gateway
git pull && make update
```

### 2. Access Control

```bash
# Regular security audit
./scripts/security-hardening.sh check

# Review access logs
sudo journalctl -u ssh -f

# Monitor failed login attempts
./scripts/monitoring-system.sh security
```

### 3. Certificate Management

```bash
# Generate new SSH keys regularly
ssh-keygen -t ed25519 -f ~/.ssh/pi-gateway-new

# Update WireGuard keys
./scripts/vpn-setup.sh regenerate-keys

# Backup security keys
./scripts/backup-config.sh create security-keys --include-keys
```

## Performance Tuning

### 1. System Optimization

```bash
# CPU and memory optimization
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

# Network performance
./scripts/network-optimizer.sh optimize --profile high-performance

# Storage optimization
sudo tune2fs -o journal_data_writeback /dev/mmcblk0p2
```

### 2. Container Optimization

```bash
# Resource limits
docker update --memory="512m" --cpus="0.5" container-name

# Image optimization
docker system prune -a

# Performance monitoring
./scripts/monitoring-system.sh containers
```

## Troubleshooting

### 1. Common Issues

**SSH Connection Issues:**
```bash
# Check SSH service
sudo systemctl status ssh

# Verify firewall
sudo ufw status

# Check logs
sudo journalctl -u ssh -f
```

**VPN Connection Problems:**
```bash
# Check WireGuard status
sudo wg show

# Restart VPN service
sudo systemctl restart wg-quick@wg0

# Check configuration
./scripts/vpn-client-manager.sh list
```

**Container Issues:**
```bash
# Check Docker service
sudo systemctl status docker

# View container logs
docker logs container-name

# Restart failed containers
docker restart container-name
```

### 2. Log Analysis

```bash
# System logs
sudo journalctl -f

# Pi Gateway logs
tail -f /var/log/pi-gateway/*.log

# Application logs
./scripts/monitoring-system.sh logs
```

### 3. Emergency Procedures

**System Recovery:**
```bash
# Boot from recovery media
# Mount SD card
# Fix configuration files
# Restore from backup
./scripts/backup-config.sh restore emergency
```

**Network Recovery:**
```bash
# Reset network configuration
sudo dhclient -r && sudo dhclient

# Restart networking
sudo systemctl restart networking

# Reset firewall
sudo ufw --force reset
```

## Production Deployment Checklist

### Pre-Production

- [ ] Hardware setup completed
- [ ] Network configuration verified
- [ ] SSH key authentication working
- [ ] Firewall rules configured
- [ ] VPN server operational
- [ ] DNS configuration working
- [ ] Backup system tested

### Security Verification

- [ ] Password authentication disabled
- [ ] Firewall active and configured
- [ ] Security hardening applied
- [ ] SSH keys rotated
- [ ] System updates current
- [ ] Monitoring alerts configured
- [ ] Audit logging enabled

### Performance Validation

- [ ] Network optimization applied
- [ ] System performance tuned
- [ ] Container resources allocated
- [ ] Monitoring thresholds set
- [ ] Backup schedule verified
- [ ] Maintenance automation enabled

### Documentation

- [ ] Network diagram created
- [ ] Service inventory documented
- [ ] Recovery procedures tested
- [ ] Contact information updated
- [ ] Change management process defined

## Support and Resources

- **Documentation**: [Pi Gateway Wiki](https://github.com/vnykmshr/pi-gateway/wiki)
- **Issues**: [GitHub Issues](https://github.com/vnykmshr/pi-gateway/issues)
- **Community**: [Discussion Forum](https://github.com/vnykmshr/pi-gateway/discussions)
- **Updates**: Watch the repository for release notifications

---

**Note**: This deployment guide assumes a production environment. For development or testing, many security steps can be relaxed. Always test changes in a non-production environment first.