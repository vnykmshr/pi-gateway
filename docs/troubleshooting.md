# Pi Gateway Troubleshooting Guide

Comprehensive troubleshooting guide for common issues and solutions.

## Table of Contents

1. [Installation Issues](#installation-issues)
2. [SSH Connection Problems](#ssh-connection-problems)
3. [VPN Issues](#vpn-issues)
4. [Network Connectivity](#network-connectivity)
5. [Service Management](#service-management)
6. [Performance Issues](#performance-issues)
7. [Security Concerns](#security-concerns)
8. [Hardware Problems](#hardware-problems)
9. [Log Analysis](#log-analysis)
10. [Recovery Procedures](#recovery-procedures)

## Installation Issues

### Setup Script Fails

#### Problem: Permission denied errors during setup

```bash
# Error: Permission denied when running setup
./setup.sh: Permission denied
```

**Solution:**
```bash
# Make script executable
chmod +x setup.sh

# Verify permissions
ls -la setup.sh

# Should show: -rwxr-xr-x
```

#### Problem: Insufficient privileges

```bash
# Error: Need sudo access for system configuration
```

**Solution:**
```bash
# Add user to sudo group
sudo usermod -aG sudo $USER

# Logout and login again
exit
ssh pi@your-pi-ip

# Verify sudo access
sudo whoami
# Should output: root
```

#### Problem: Package installation fails

```bash
# Error: Unable to fetch packages
E: Unable to locate package xyz
```

**Solution:**
```bash
# Update package database
sudo apt update

# Check internet connectivity
ping 8.8.8.8

# Verify DNS resolution
nslookup google.com

# If behind proxy, configure apt:
sudo nano /etc/apt/apt.conf.d/95proxies
# Add: Acquire::http::Proxy "http://proxy:port";
```

### Configuration Issues

#### Problem: Invalid configuration values

```bash
# Error: Invalid port number in setup.conf
```

**Solution:**
```bash
# Review configuration file
nano config/setup.conf

# Common issues and fixes:
# - Port numbers: Must be 1-65535
# - IP ranges: Use valid CIDR notation (e.g., 10.13.13.0/24)
# - Booleans: Use true/false (lowercase)

# Validate configuration
./setup.sh --dry-run --validate-config
```

## SSH Connection Problems

### Cannot Connect to SSH

#### Problem: Connection refused

```bash
# Error: ssh: connect to host X.X.X.X port 22: Connection refused
```

**Solution:**
```bash
# Check if SSH service is running
sudo systemctl status ssh

# Start SSH service if stopped
sudo systemctl start ssh
sudo systemctl enable ssh

# Check SSH configuration
sudo sshd -T | grep port

# Verify firewall allows SSH
sudo ufw status | grep 22
```

#### Problem: Connection timeout

```bash
# Error: ssh: connect to host X.X.X.X port 2222: Connection timed out
```

**Solution:**
```bash
# 1. Check if you're using correct port
ssh -p 2222 pi@your-ip

# 2. Verify router port forwarding
# External Port: 2222 → Internal IP:2222

# 3. Check if Pi is accessible locally
# From same network:
ssh pi@192.168.1.100

# 4. Verify external IP/hostname
curl ifconfig.me  # Check your external IP
```

#### Problem: Permission denied (publickey)

```bash
# Error: Permission denied (publickey)
```

**Solution:**
```bash
# Check if password authentication is allowed
ssh -o PreferredAuthentications=password pi@your-ip

# Enable password authentication temporarily
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication yes
sudo systemctl restart ssh

# Add your public key
ssh-copy-id pi@your-ip

# Re-disable password authentication
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh
```

### SSH Key Issues

#### Problem: SSH key not accepted

```bash
# Error: Server rejected SSH key
```

**Solution:**
```bash
# Check key permissions on client
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Check authorized_keys on Pi
ls -la ~/.ssh/authorized_keys
# Should be: -rw------- (600)

# Fix permissions if needed
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

# Verify key is in authorized_keys
cat ~/.ssh/authorized_keys
```

## VPN Issues

### WireGuard Won't Start

#### Problem: WireGuard service fails to start

```bash
# Error: Job for wg-quick@wg0.service failed
```

**Solution:**
```bash
# Check WireGuard configuration
sudo wg-quick up wg0

# Common configuration errors:
sudo nano /etc/wireguard/wg0.conf

# 1. Check interface IP format
# Correct: Address = 10.13.13.1/24
# Wrong:   Address = 10.13.13.1

# 2. Verify private key exists
# Check: PrivateKey = [base64-encoded-key]

# 3. Check port conflicts
sudo ss -ulpn | grep 51820

# 4. Restart service
sudo systemctl restart wg-quick@wg0
```

#### Problem: VPN clients can't connect

```bash
# Error: Handshake timeout or no response
```

**Solution:**
```bash
# 1. Check server status
sudo wg show

# 2. Verify firewall allows VPN port
sudo ufw status | grep 51820
# If missing, add rule:
sudo ufw allow 51820/udp

# 3. Check router port forwarding
# External Port: 51820 → Internal IP:51820 (UDP)

# 4. Verify client configuration
# Check client has correct:
# - Server endpoint (your-hostname.duckdns.org:51820)
# - Correct public key
# - Allowed IPs (0.0.0.0/0 for full tunnel)
```

### VPN Performance Issues

#### Problem: Slow VPN speeds

**Solution:**
```bash
# 1. Check Pi CPU usage during VPN use
htop

# 2. Optimize WireGuard MTU
sudo nano /etc/wireguard/wg0.conf
# Add to [Interface]:
MTU = 1420

# 3. Enable hardware acceleration (Pi 4/5)
echo "dtoverlay=vc4-fkms-v3d" | sudo tee -a /boot/config.txt

# 4. Restart WireGuard
sudo systemctl restart wg-quick@wg0
```

## Network Connectivity

### DNS Resolution Problems

#### Problem: Can't resolve hostnames

```bash
# Error: Temporary failure in name resolution
```

**Solution:**
```bash
# Test DNS resolution
nslookup google.com

# Check DNS configuration
cat /etc/resolv.conf

# Set reliable DNS servers
sudo nano /etc/systemd/resolved.conf
# Add:
# DNS=8.8.8.8 1.1.1.1
# Domains=~.

# Restart DNS service
sudo systemctl restart systemd-resolved
```

### Dynamic DNS Issues

#### Problem: DDNS not updating

```bash
# Error: Dynamic DNS hostname not resolving
```

**Solution:**
```bash
# Check DDNS service status
sudo systemctl status ddclient

# Review DDNS logs
sudo journalctl -u ddclient

# Test manual update (DuckDNS example)
curl "https://www.duckdns.org/update?domains=yourdomain&token=yourtoken&ip="

# Verify external IP
curl ifconfig.me

# Check DDNS configuration
sudo nano /etc/ddclient.conf
```

### Router Configuration

#### Problem: Port forwarding not working

**Solution:**
```bash
# 1. Verify Pi has static/reserved IP
ip addr show

# 2. Test from internal network first
ssh pi@192.168.1.100

# 3. Check router port forwarding rules:
# Service: SSH
# External Port: 2222
# Internal IP: 192.168.1.100
# Internal Port: 2222
# Protocol: TCP

# 4. Test external access
# From mobile data or different network:
ssh -p 2222 pi@your-external-ip
```

## Service Management

### Service Won't Start

#### Problem: Systemd service fails

```bash
# Error: Failed to start service
```

**Solution:**
```bash
# Check service status
sudo systemctl status service-name

# View detailed logs
sudo journalctl -u service-name

# Check service file syntax
sudo systemd-analyze verify /etc/systemd/system/service-name.service

# Reload systemd if service file changed
sudo systemctl daemon-reload

# Try manual start for debugging
sudo /path/to/service --debug
```

### Firewall Blocking Services

#### Problem: UFW blocking legitimate traffic

```bash
# Error: Connection refused despite service running
```

**Solution:**
```bash
# Check firewall status
sudo ufw status verbose

# Allow specific service
sudo ufw allow 22/tcp
sudo ufw allow 51820/udp

# Allow from specific network
sudo ufw allow from 192.168.1.0/24

# Temporarily disable firewall for testing
sudo ufw disable
# Test service
# Re-enable firewall
sudo ufw enable
```

## Performance Issues

### High CPU Usage

#### Problem: Pi running slowly or overheating

**Solution:**
```bash
# Check running processes
htop
top

# Identify CPU-heavy processes
ps aux --sort=-%cpu | head -10

# Check system temperature
vcgencmd measure_temp

# If overheating (>80°C):
# 1. Improve cooling/ventilation
# 2. Reduce overclocking
# 3. Check for runaway processes

# Monitor process continuously
watch -n 1 "ps aux --sort=-%cpu | head -10"
```

### Memory Issues

#### Problem: Out of memory errors

```bash
# Error: Cannot allocate memory
```

**Solution:**
```bash
# Check memory usage
free -h

# Check swap usage
swapon --show

# Add swap file if needed (temporary fix)
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Find memory-hungry processes
ps aux --sort=-%mem | head -10

# Restart memory-heavy services
sudo systemctl restart service-name
```

### Storage Issues

#### Problem: Disk full or running out of space

```bash
# Error: No space left on device
```

**Solution:**
```bash
# Check disk usage
df -h

# Find large directories
sudo du -sh /* | sort -hr

# Clean package cache
sudo apt clean
sudo apt autoremove

# Clear logs if needed
sudo journalctl --vacuum-time=7d

# Find and remove large files
find / -type f -size +100M 2>/dev/null
```

## Security Concerns

### Failed Login Attempts

#### Problem: Many failed login attempts in logs

```bash
# Error: Multiple "Failed password" entries
```

**Solution:**
```bash
# Check authentication logs
sudo grep "Failed password" /var/log/auth.log

# Verify fail2ban is active
sudo fail2ban-client status

# Check SSH jail status
sudo fail2ban-client status sshd

# Ban specific IP manually
sudo fail2ban-client set sshd banip x.x.x.x

# Strengthen SSH security:
sudo nano /etc/ssh/sshd_config
# Set: MaxAuthTries 3
# Set: ClientAliveInterval 300
# Set: ClientAliveCountMax 2
```

### Suspicious Network Activity

#### Problem: Unusual network connections

**Solution:**
```bash
# Check active connections
sudo ss -tupln

# Monitor network activity
sudo netstat -tulpn | grep LISTEN

# Check for unusual processes
ps aux | grep -E "(nc|netcat|socat)"

# Review UFW logs for blocked attempts
sudo tail -f /var/log/ufw.log

# Check for rootkits (install rkhunter)
sudo apt install rkhunter
sudo rkhunter --check
```

## Hardware Problems

### SD Card Issues

#### Problem: SD card corruption or read-only filesystem

```bash
# Error: Read-only file system
```

**Solution:**
```bash
# Check filesystem status
mount | grep "ro,"

# Remount as read-write (temporary)
sudo mount -o remount,rw /

# Check SD card health
sudo fsck /dev/mmcblk0p2

# If corruption detected:
# 1. Backup important data immediately
# 2. Consider replacing SD card
# 3. Use SSD boot if possible

# Enable read-only mode to prevent further corruption
sudo raspi-config
# Advanced Options > Overlay FS > Enable
```

### Temperature Issues

#### Problem: Pi overheating and throttling

```bash
# Check temperature and throttling
vcgencmd measure_temp
vcgencmd get_throttled
```

**Solution:**
```bash
# Monitor temperature continuously
watch -n 2 vcgencmd measure_temp

# If throttling detected (value != 0x0):
# 1. Improve case ventilation
# 2. Add heatsinks or fan
# 3. Reduce overclocking
# 4. Check ambient temperature

# Temporary CPU frequency check
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
```

## Log Analysis

### Understanding Common Log Entries

#### SSH Logs

```bash
# Successful login
sudo grep "Accepted" /var/log/auth.log

# Failed attempts
sudo grep "Failed" /var/log/auth.log

# SSH key authentication
sudo grep "publickey" /var/log/auth.log
```

#### VPN Logs

```bash
# WireGuard service logs
sudo journalctl -u wg-quick@wg0

# Connection handshakes
sudo grep "handshake" /var/log/syslog
```

#### System Logs

```bash
# Boot messages
sudo journalctl -b

# Service failures
sudo journalctl -p err

# Last hour of logs
sudo journalctl --since "1 hour ago"
```

## Recovery Procedures

### Emergency SSH Access

#### Problem: Locked out of SSH

**Solution:**
```bash
# Physical access to Pi:
# 1. Connect keyboard and monitor
# 2. Login locally
# 3. Check SSH service and firewall
sudo systemctl status ssh
sudo ufw status

# Alternative: Enable SSH via SD card
# 1. Remove SD card
# 2. Mount on computer
# 3. Create empty file named 'ssh' in boot partition
# 4. Reinsert SD card and boot Pi
```

### Configuration Recovery

#### Problem: Broken configuration preventing boot

**Solution:**
```bash
# Boot into recovery mode:
# 1. Add 'init=/bin/bash' to cmdline.txt
# 2. Mount filesystem as read-write:
mount -o remount,rw /

# Restore from backup
cd /opt/pi-gateway
./scripts/backup-config.sh restore latest-backup.tar.gz

# Or reset to defaults
./setup.sh --reset-config
```

### Full System Recovery

#### Problem: System completely unresponsive

**Solution:**
```bash
# 1. Create new SD card with fresh Pi OS
# 2. Boot with new card
# 3. Mount old SD card (USB adapter)
# 4. Recover data from /home and /etc
# 5. Reinstall Pi Gateway
# 6. Restore configuration from backup
```

## Quick Diagnostic Commands

```bash
# System overview
./scripts/service-status.sh              # Pi Gateway status
sudo systemctl --failed                 # Failed services
df -h && free -h                       # Disk and memory
vcgencmd measure_temp                   # Temperature

# Network diagnostics
ping 8.8.8.8                          # Internet connectivity
sudo ss -tulpn                        # Listening ports
sudo ufw status                       # Firewall rules
sudo wg show                          # VPN status

# Security check
sudo fail2ban-client status           # Intrusion detection
sudo grep "Failed" /var/log/auth.log  # Failed logins
sudo journalctl -p err --since today  # Today's errors

# Performance check
htop                                  # Resource usage
sudo iotop                           # Disk I/O
sudo nethogs                         # Network usage per process
```

---

**Getting Help:**

If you can't resolve an issue:

1. **Gather Information**: Run diagnostic commands above
2. **Check Logs**: Look for error messages in relevant logs
3. **Search Issues**: Check [GitHub Issues](https://github.com/vnykmshr/pi-gateway/issues)
4. **Create Issue**: Provide system info, logs, and steps to reproduce

**Previous**: [Usage Guide](usage.md) | **Back**: [README](../README.md)