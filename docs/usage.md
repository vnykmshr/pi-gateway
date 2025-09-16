# Pi Gateway Usage Guide

Daily operations and management guide for your Pi Gateway homelab system.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [VPN Management](#vpn-management)
3. [SSH Access](#ssh-access)
4. [Remote Desktop](#remote-desktop)
5. [Service Management](#service-management)
6. [Monitoring & Maintenance](#monitoring--maintenance)
7. [Security Management](#security-management)
8. [Backup & Recovery](#backup--recovery)
9. [Troubleshooting](#troubleshooting)

## Daily Operations

### Quick Status Check

```bash
# Check all services status
make status

# Detailed service report
./scripts/service-status.sh

# View recent logs
make logs
```

### System Health

```bash
# Check system resources
htop
# or
top

# Disk usage
df -h

# Memory usage
free -h

# Network connections
ss -tulpn
```

## VPN Management

### Client Management

#### Add New VPN Client

```bash
# Generate new client configuration
sudo ./scripts/vpn-client-add.sh client-name

# Configuration saved to: /etc/wireguard/clients/client-name.conf
# Share this file with the client device
```

#### Remove VPN Client

```bash
# Remove client access
sudo ./scripts/vpn-client-remove.sh client-name

# This will:
# - Remove client from server configuration
# - Restart WireGuard service
# - Archive client configuration
```

#### List Active Clients

```bash
# Show connected VPN clients
sudo wg show

# Detailed client information
sudo ./scripts/vpn-client-list.sh
```

### VPN Server Management

#### Restart VPN Service

```bash
# Restart WireGuard
sudo systemctl restart wg-quick@wg0

# Check service status
sudo systemctl status wg-quick@wg0
```

#### Update VPN Configuration

```bash
# Edit main VPN configuration
sudo nano /etc/wireguard/wg0.conf

# Restart service after changes
sudo systemctl restart wg-quick@wg0
```

### Client Device Setup

#### Windows

1. Install [WireGuard for Windows](https://www.wireguard.com/install/)
2. Import configuration file from `/etc/wireguard/clients/`
3. Activate tunnel

#### macOS

```bash
# Install WireGuard
brew install wireguard-tools

# Import configuration
sudo cp client-name.conf /etc/wireguard/
sudo wg-quick up client-name
```

#### iOS/Android

1. Install WireGuard app from App Store/Play Store
2. Scan QR code or import configuration file
3. Activate connection

#### Linux

```bash
# Install WireGuard
sudo apt install wireguard

# Import configuration
sudo cp client-name.conf /etc/wireguard/
sudo wg-quick up client-name

# Auto-start on boot
sudo systemctl enable wg-quick@client-name
```

## SSH Access

### Connecting to Your Pi

#### From External Network

```bash
# Using dynamic DNS hostname
ssh -p 2222 pi@your-hostname.duckdns.org

# Using external IP (if static)
ssh -p 2222 pi@your.external.ip.address
```

#### From Internal Network

```bash
# Direct internal IP
ssh pi@192.168.1.100

# Or via VPN
ssh pi@10.13.13.1
```

### SSH Key Management

#### Add New SSH Key

```bash
# On your Pi, add a new authorized key
echo "ssh-rsa AAAAB3N... user@device" >> ~/.ssh/authorized_keys
```

#### Remove SSH Key

```bash
# Edit authorized_keys file
nano ~/.ssh/authorized_keys

# Remove the unwanted key line
# Save and exit
```

#### Generate SSH Key Pair (on client)

```bash
# Generate new key pair
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy public key to Pi
ssh-copy-id -p 2222 pi@your-hostname.duckdns.org
```

## Remote Desktop

### VNC Access

#### Enable VNC Service

```bash
# Start VNC service
sudo systemctl start vncserver@1

# Enable auto-start
sudo systemctl enable vncserver@1

# Check status
sudo systemctl status vncserver@1
```

#### VNC Client Connection

```bash
# VNC connection details
Host: your-hostname.duckdns.org:5900
# or
Host: your-external-ip:5900

# Through VPN
Host: 10.13.13.1:5900
```

### xRDP Access

#### RDP Connection

```bash
# RDP connection details
Host: your-hostname.duckdns.org:3389
Username: pi
Password: your-password
```

## Service Management

### Core Services

#### SSH Service

```bash
# Restart SSH
sudo systemctl restart ssh

# Check SSH configuration
sudo sshd -T

# View SSH logs
sudo journalctl -u ssh
```

#### Firewall Management

```bash
# Check firewall status
sudo ufw status verbose

# Add new rule
sudo ufw allow from 192.168.1.0/24 to any port 22

# Remove rule
sudo ufw delete allow 22

# Reset firewall (caution!)
sudo ufw --force reset
```

#### Fail2ban

```bash
# Check banned IPs
sudo fail2ban-client status sshd

# Unban IP address
sudo fail2ban-client set sshd unbanip 1.2.3.4

# Check fail2ban logs
sudo tail -f /var/log/fail2ban.log
```

### Custom Services

#### Add Custom Service

```bash
# Create service file
sudo nano /etc/systemd/system/my-service.service

# Enable and start
sudo systemctl enable my-service
sudo systemctl start my-service
```

## Monitoring & Maintenance

### System Monitoring

#### Resource Usage

```bash
# CPU and memory
htop

# Disk I/O
iotop

# Network usage
iftop

# System temperature
vcgencmd measure_temp
```

#### Log Monitoring

```bash
# System logs
sudo journalctl -f

# SSH access logs
sudo tail -f /var/log/auth.log

# VPN logs
sudo journalctl -u wg-quick@wg0 -f

# Firewall logs
sudo tail -f /var/log/ufw.log
```

### Automated Monitoring

#### Set Up Log Rotation

```bash
# Configure logrotate
sudo nano /etc/logrotate.d/pi-gateway

# Example configuration:
/var/log/pi-gateway/*.log {
    weekly
    rotate 4
    compress
    notifempty
    create 644 pi-gateway pi-gateway
}
```

#### Health Check Script

```bash
# Run periodic health checks
crontab -e

# Add line for hourly health check:
0 * * * * /opt/pi-gateway/scripts/health-check.sh
```

### Updates & Upgrades

#### System Updates

```bash
# Update package lists
sudo apt update

# Upgrade packages
sudo apt upgrade -y

# Upgrade distribution (caution!)
sudo apt full-upgrade

# Remove unnecessary packages
sudo apt autoremove
```

#### Pi Gateway Updates

```bash
# Update Pi Gateway
cd /opt/pi-gateway
git pull origin main

# Run update script if available
./scripts/update.sh
```

## Security Management

### Security Monitoring

#### Check for Intrusions

```bash
# Review authentication logs
sudo grep "Failed password" /var/log/auth.log

# Check fail2ban activity
sudo fail2ban-client status

# Review UFW logs
sudo tail -f /var/log/ufw.log
```

#### Security Audit

```bash
# Check listening services
sudo ss -tulpn

# Review user accounts
cat /etc/passwd

# Check sudo users
grep sudo /etc/group

# Review cron jobs
sudo crontab -l
```

### Hardening Maintenance

#### Update Security Rules

```bash
# Update fail2ban filters
sudo nano /etc/fail2ban/jail.local

# Restart fail2ban
sudo systemctl restart fail2ban

# Update firewall rules
sudo ufw status numbered
sudo ufw delete [number]
```

## Backup & Recovery

### Configuration Backup

#### Create Backup

```bash
# Full configuration backup
make backup-config

# Manual backup
./scripts/backup-config.sh backup

# Backup to external location
./scripts/backup-config.sh backup --location /mnt/usb/
```

#### List Backups

```bash
# List available backups
./scripts/backup-config.sh list

# Show backup details
./scripts/backup-config.sh verify backup-name.tar.gz
```

#### Restore Configuration

```bash
# Restore from backup
./scripts/backup-config.sh restore backup-name.tar.gz

# Selective restore
./scripts/backup-config.sh restore backup-name.tar.gz --component ssh
```

### System Backup

#### Full System Backup

```bash
# Create system image (external system)
sudo dd if=/dev/sdX of=pi-backup.img bs=4M status=progress

# Compress image
gzip pi-backup.img
```

#### Incremental Backup

```bash
# Backup important directories
rsync -av --exclude='.cache' /home/pi/ /mnt/backup/home/
rsync -av /etc/ /mnt/backup/etc/
rsync -av /opt/pi-gateway/ /mnt/backup/pi-gateway/
```

## Troubleshooting

### Common Issues

#### Can't Connect via SSH

```bash
# Check SSH service
sudo systemctl status ssh

# Verify port configuration
sudo grep Port /etc/ssh/sshd_config

# Check firewall
sudo ufw status

# Test local connection
ssh pi@localhost
```

#### VPN Not Working

```bash
# Check WireGuard status
sudo systemctl status wg-quick@wg0

# Verify configuration
sudo wg show

# Check firewall rules
sudo ufw status | grep 51820

# Test connectivity
ping 10.13.13.1
```

#### High CPU/Memory Usage

```bash
# Identify resource-heavy processes
htop
top

# Check for runaway processes
ps aux --sort=-%cpu | head -10
ps aux --sort=-%mem | head -10

# Restart problematic services
sudo systemctl restart service-name
```

### Performance Optimization

#### Reduce Memory Usage

```bash
# Adjust GPU memory split
sudo raspi-config
# Advanced Options > Memory Split > 16

# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable cups
```

#### Network Optimization

```bash
# Adjust network settings
echo 'net.core.rmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' | sudo tee -a /etc/sysctl.conf

# Apply changes
sudo sysctl -p
```

## Quick Reference Commands

```bash
# Service status
make status                          # All services overview
./scripts/service-status.sh         # Detailed status report

# VPN management
sudo wg show                        # Show VPN status
sudo ./scripts/vpn-client-add.sh   # Add VPN client
sudo ./scripts/vpn-client-list.sh  # List VPN clients

# Logs
make logs                           # Recent logs
sudo journalctl -f                  # Live log stream
sudo tail -f /var/log/auth.log     # SSH access logs

# Security
sudo ufw status                     # Firewall status
sudo fail2ban-client status        # Intrusion detection
sudo ss -tulpn                     # Listening ports

# Backup
make backup-config                  # Create configuration backup
./scripts/backup-config.sh list    # List backups
```

---

**Next**: [Troubleshooting](troubleshooting.md) | **Previous**: [Setup Guide](setup-guide.md)