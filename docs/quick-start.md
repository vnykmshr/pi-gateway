# Pi Gateway Quick Start Guide

Transform your Raspberry Pi into a secure personal server in 15 minutes with automated setup, VPN access, and professional security hardening.

## 🎯 What You'll Get

After completion, you'll have:
- **🔐 Secure SSH access** with key-based authentication
- **🌐 Personal VPN server** for secure remote access
- **🛡️ Hardened security** with firewall and intrusion prevention
- **📱 Remote desktop** access via VNC
- **🌍 Dynamic DNS** for reliable external access
- **📊 System monitoring** and health checks

---

## ⚡ Quick Start (Recommended)

**For experienced users:** Skip to [One-Command Installation](#quick-installation)

**For beginners:** Follow the complete guide below for best results

---

## 📋 Before You Begin

### ✅ Pre-Setup Checklist

Complete these steps **before** running Pi Gateway setup:

#### 1. **Prepare Your Raspberry Pi**
- [ ] **Raspberry Pi 4 or newer** (2GB+ RAM, 4GB+ recommended)
- [ ] **32GB+ MicroSD card** with Raspberry Pi OS installed
- [ ] **Reliable power supply** (official Pi adapter recommended)
- [ ] **Ethernet cable** connected to your router

#### 2. **Enable SSH Access**

**Option A: Enable SSH before first boot (recommended)**
```bash
# After flashing Raspberry Pi OS to SD card:
# 1. Don't eject the SD card yet
# 2. Open the 'boot' partition on your computer
# 3. Create an empty file named 'ssh' (no extension)

# On Windows:
# Right-click in boot folder → New → Text Document → Name it 'ssh' (remove .txt)

# On Mac/Linux:
touch /Volumes/boot/ssh
```

**Option B: Enable SSH after first boot**
```bash
# Connect monitor/keyboard to Pi, then run:
sudo systemctl enable ssh
sudo systemctl start ssh
```

#### 3. **Find Your Pi's IP Address**

**Method 1: Check your router's admin panel**
- Open router admin (usually `192.168.1.1` or `192.168.0.1`)
- Look for "Connected Devices" or "DHCP Clients"
- Find device named "raspberrypi"

**Method 2: Use network scanning**
```bash
# On Mac:
brew install nmap
nmap -sn 192.168.1.0/24 | grep -B2 -A1 "Raspberry Pi"

# On Windows:
# Download "Advanced IP Scanner" (free tool)

# On Linux:
sudo nmap -sn 192.168.1.0/24 | grep -B2 -A1 "Raspberry Pi"
```

**Method 3: Use Pi directly**
```bash
# Connect monitor/keyboard to Pi and run:
hostname -I
```

#### 4. **Test SSH Connection**

Replace `YOUR_PI_IP` with your Pi's actual IP address:

```bash
# Test connection (default password: raspberry)
ssh pi@YOUR_PI_IP

# If this works, you're ready to proceed!
# If not, see troubleshooting section below
```

---

## 🚀 Installation Options

### Option 1: One-Command Installation (Recommended)

**For users comfortable with command line:**

```bash
# Run on your Pi via SSH
curl -sSL https://raw.githubusercontent.com/vnykmshr/pi-gateway/main/scripts/quick-install.sh | bash
```

### Option 2: Manual Installation (More Control)

**For users who want to see each step:**

```bash
# 1. Connect to your Pi via SSH
ssh pi@YOUR_PI_IP

# 2. Clone the repository
git clone https://github.com/vnykmshr/pi-gateway.git
cd pi-gateway

# 3. Run pre-flight checks (recommended)
./scripts/pre-flight-check.sh

# 4. Start interactive setup
sudo ./setup.sh

# OR run automated setup
sudo ./setup.sh --non-interactive
```

### Option 3: Guided Interactive Setup

**For beginners who want explanations:**

```bash
# Run with interactive prompts and explanations
curl -sSL https://raw.githubusercontent.com/vnykmshr/pi-gateway/main/scripts/quick-install.sh | bash -s -- --interactive
```

---

## ⏱️ What to Expect During Setup

The setup process typically takes **10-20 minutes** depending on your internet speed:

```
🔍 Pre-flight checks           [ 1 min ]  ✅ System validation
🔄 Installing dependencies     [ 3-5 min ] ⬇️ Download packages
🛡️ Security hardening         [ 2-3 min ] 🔒 System protection
🔐 SSH configuration          [ 1 min ]   🔑 Key-based auth
🌐 VPN server setup           [ 3-5 min ] 🚀 WireGuard config
🔥 Firewall configuration     [ 1-2 min ] 🛡️ Network security
📱 Remote desktop (optional)  [ 2-3 min ] 🖥️ VNC access
🌍 Dynamic DNS (optional)     [ 1-2 min ] 🌐 External access
```

### 📊 Progress Indicators

You'll see real-time progress like this:
```
Progress: [████████░░░░] 60% (3/5 complete)
Current Phase: VPN Server Setup
Description: WireGuard VPN configuration
Estimated remaining: ~4 minutes
```

---

## 🔧 Post-Installation Setup

### 1. **Generate SSH Keys (Highly Recommended)**

**On your local computer** (not the Pi):

```bash
# Generate a new SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/pi-gateway -C "your-email@example.com"

# Copy the public key to your Pi
ssh-copy-id -i ~/.ssh/pi-gateway.pub pi@YOUR_PI_IP

# Test key-based login
ssh -i ~/.ssh/pi-gateway pi@YOUR_PI_IP

# If successful, password login will be disabled automatically
```

### 2. **Create Your First VPN Client**

```bash
# Add a VPN client for your laptop
sudo ./scripts/vpn-client-manager.sh add my-laptop

# Show QR code for mobile setup
sudo ./scripts/vpn-client-manager.sh show my-phone --qr

# List all VPN clients
sudo ./scripts/vpn-client-manager.sh list
```

### 3. **Verify Everything Works**

```bash
# Check system status
./scripts/status-dashboard.sh

# Test all services
sudo ./scripts/health-check.sh

# View system information
./scripts/system-info.sh
```

---

## 🌐 Accessing Your Services

After setup completion, you can access:

| Service | Local Access | Remote Access (via VPN) |
|---------|-------------|-------------------------|
| **SSH** | `ssh pi@192.168.1.XXX` | `ssh pi@10.8.0.1` |
| **Web Dashboard** | `http://192.168.1.XXX:8080` | `http://10.8.0.1:8080` |
| **VNC Remote Desktop** | `192.168.1.XXX:5901` | `10.8.0.1:5901` |
| **System Monitor** | `http://192.168.1.XXX:3000` | `http://10.8.0.1:3000` |

### 📱 VPN Client Setup

**For mobile devices:**
1. Install WireGuard app from app store
2. Scan QR code generated during setup
3. Enable VPN connection

**For computers:**
1. Install WireGuard client
2. Import the `.conf` file from `/home/pi/vpn-clients/`
3. Connect to access your home network securely

---

## 🔍 Troubleshooting

### ❌ **"Permission denied" when connecting via SSH**

```bash
# Check if SSH is running on Pi
ping YOUR_PI_IP  # Should respond

# Try different username (older Pi OS uses 'pi', newer uses your custom username)
ssh your-username@YOUR_PI_IP

# Enable SSH if needed (connect monitor/keyboard to Pi)
sudo systemctl enable ssh
sudo systemctl start ssh
```

### ❌ **"Connection refused" errors**

```bash
# Check if Pi is reachable
ping YOUR_PI_IP

# Try different SSH port (Pi Gateway may have changed it)
ssh -p 2222 pi@YOUR_PI_IP

# Check firewall status
sudo ufw status
```

### ❌ **"Pre-flight checks failed"**

Run individual checks to identify issues:
```bash
# Test internet connectivity
ping 8.8.8.8

# Check disk space (need 8GB+)
df -h

# Verify sudo access
sudo echo "Sudo working"

# Update package lists
sudo apt update
```

### ❌ **Setup hangs or fails**

```bash
# Check setup logs
tail -f /tmp/pi-gateway-setup.log

# Restart with verbose output
sudo ./setup.sh --verbose

# Run in dry-run mode to test
sudo ./setup.sh --dry-run
```

### ❌ **VPN not working after setup**

```bash
# Check VPN server status
sudo wg show

# Restart VPN service
sudo systemctl restart wg-quick@wg0

# Check firewall allows VPN port
sudo ufw status | grep 51820
```

---

## 🚨 Emergency Access

If you get locked out of SSH:

1. **Physical access**: Connect monitor/keyboard to Pi
2. **Reset SSH config**:
   ```bash
   sudo systemctl restart ssh
   sudo ufw allow ssh
   ```
3. **Restore backup**: Configuration backups are in `/var/backups/pi-gateway/`

---

## 📚 Next Steps

### 🔒 **Enhanced Security**
```bash
# Enable additional security features
sudo ./scripts/security-hardening.sh --advanced

# Set up intrusion detection
sudo ./scripts/monitoring-system.sh setup-alerts

# Configure automated backups
sudo ./scripts/backup-config.sh schedule
```

### 🐳 **Add Services with Docker**
```bash
# Install container support
sudo ./scripts/container-support.sh install docker

# Popular homelab applications
sudo ./scripts/container-manager.sh install pi-hole      # Ad blocking
sudo ./scripts/container-manager.sh install nextcloud   # Personal cloud
sudo ./scripts/container-manager.sh install jellyfin    # Media server
```

### 📱 **Mobile Management**
- Access web dashboard: `http://YOUR_PI_IP:8080`
- Install WireGuard app for secure remote access
- Set up push notifications for system alerts

---

## 💬 Getting Help

### 📖 **Documentation**
- [Complete Setup Guide](setup-guide.md) - Detailed installation instructions
- [Troubleshooting Guide](troubleshooting.md) - Solutions for common issues
- [Usage Guide](usage.md) - How to use installed services

### 🐛 **Support**
- [GitHub Issues](https://github.com/vnykmshr/pi-gateway/issues) - Bug reports and feature requests
- [Discussions](https://github.com/vnykmshr/pi-gateway/discussions) - Community help and questions

### 🛠️ **Advanced Topics**
- [Extension Development](extensions.md) - Creating custom services
- [Security Best Practices](security.md) - Hardening and compliance
- [API Documentation](api.md) - Programmatic access

---

## ✅ Success Checklist

Confirm your Pi Gateway is working correctly:

- [ ] **SSH access** with key-based authentication
- [ ] **VPN connection** from external device
- [ ] **Web dashboard** accessible locally and via VPN
- [ ] **Firewall active** and properly configured
- [ ] **System monitoring** showing healthy status
- [ ] **Backup system** configured and tested

**🎉 Congratulations!** Your Pi Gateway is ready. You now have a professional-grade homelab foundation that's secure, accessible, and ready for expansion.

---

*⚡ **Pro tip**: Bookmark your Pi's web dashboard and set up the VPN on your phone first for convenient mobile access to your homelab.*