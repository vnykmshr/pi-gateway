# Pi Gateway Dashboard Extension

Simple web dashboard for monitoring Pi Gateway status and managing services.

## Features

- Real-time system status monitoring
- Service management interface
- VPN client management
- Log viewing and analysis
- Configuration backup/restore
- Mobile-responsive design

## Requirements

- Node.js 16+ (automatically installed)
- Port 3000 available
- Web browser for access

## Installation

The extension is automatically available when Pi Gateway is installed. To enable:

```bash
# Enable dashboard in Pi Gateway configuration
echo "ENABLE_DASHBOARD=true" >> config/setup.conf

# Run Pi Gateway setup (dashboard will be included)
./setup.sh

# Or install dashboard extension separately
./extensions/example-dashboard/setup.sh
```

## Configuration

Edit `config/dashboard.conf` to customize:

```bash
# Dashboard Configuration
DASHBOARD_PORT=3000
DASHBOARD_BIND_ADDRESS=0.0.0.0
ENABLE_AUTHENTICATION=true
SESSION_SECRET=random-secret-key

# Monitoring Settings
REFRESH_INTERVAL=30
ENABLE_ALERTS=true
ALERT_CPU_THRESHOLD=80
ALERT_MEMORY_THRESHOLD=90
```

## Usage

### Accessing the Dashboard

```bash
# Local access
http://localhost:3000

# Remote access (through VPN or port forwarding)
http://your-pi-ip:3000
http://your-ddns-hostname.duckdns.org:3000
```

### Default Credentials

- **Username**: `admin`
- **Password**: Generated during setup (check `/var/log/pi-gateway-dashboard.log`)

### Features

1. **System Overview**
   - CPU, memory, and disk usage
   - System temperature
   - Network statistics
   - Service status

2. **VPN Management**
   - Add/remove VPN clients
   - View active connections
   - Download client configurations

3. **Service Control**
   - Start/stop/restart services
   - View service logs
   - Check service health

4. **Configuration**
   - Backup/restore configurations
   - Edit service settings
   - Update system

## Security

- Authentication required by default
- HTTPS support (certificate setup required)
- Rate limiting on API endpoints
- Session management
- Input validation and sanitization

## Troubleshooting

### Dashboard Not Accessible

```bash
# Check service status
sudo systemctl status pi-gateway-dashboard

# Check logs
sudo journalctl -u pi-gateway-dashboard -f

# Verify port is open
sudo ss -tulpn | grep 3000

# Check firewall
sudo ufw status | grep 3000
```

### Performance Issues

```bash
# Check system resources
htop

# Restart dashboard service
sudo systemctl restart pi-gateway-dashboard

# Check for errors
sudo journalctl -u pi-gateway-dashboard --since "10 minutes ago"
```

### Authentication Problems

```bash
# Reset admin password
sudo /opt/pi-gateway-dashboard/scripts/reset-password.sh

# Check authentication logs
sudo tail -f /var/log/pi-gateway-dashboard.log | grep auth
```

## Development

### Local Development

```bash
# Clone and setup
git clone https://github.com/vnykmshr/pi-gateway.git
cd pi-gateway/extensions/example-dashboard

# Install dependencies
npm install

# Start development server
npm run dev

# Dashboard available at http://localhost:3001
```

### API Endpoints

```bash
# System status
GET /api/status

# Service management
GET /api/services
POST /api/services/:service/start
POST /api/services/:service/stop
POST /api/services/:service/restart

# VPN management
GET /api/vpn/clients
POST /api/vpn/clients
DELETE /api/vpn/clients/:name

# Logs
GET /api/logs/:service
```

## License

Same as Pi Gateway - MIT License