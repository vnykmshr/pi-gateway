#!/bin/bash
#
# Pi Gateway Dashboard Extension Setup
# Simple web dashboard for Pi Gateway management
#

set -euo pipefail

# Extension metadata
readonly EXTENSION_NAME="example-dashboard"
readonly EXTENSION_VERSION="1.0.0"
readonly SERVICE_NAME="pi-gateway-dashboard"
readonly SERVICE_PORT="3000"
readonly SERVICE_USER="pi-dashboard"

# Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PI_GATEWAY_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly APP_DIR="/opt/pi-gateway-dashboard"
readonly CONFIG_FILE="/etc/pi-gateway-dashboard.conf"
readonly LOG_FILE="/var/log/pi-gateway-dashboard.log"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Logging functions
success() { echo -e "  ${GREEN}✓${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
header() { echo -e "\n${CYAN}$1${NC}\n"; }

# Source Pi Gateway common functions if available
if [[ -f "$PI_GATEWAY_ROOT/scripts/common.sh" ]]; then
    source "$PI_GATEWAY_ROOT/scripts/common.sh"
fi

# Check requirements
check_requirements() {
    header "🔍 Checking Requirements"

    # Check if running with appropriate privileges
    if [[ $EUID -ne 0 ]] && [[ "${ALLOW_NON_ROOT:-false}" != "true" ]]; then
        error "This extension requires root privileges"
        info "Run with: sudo $0"
        exit 1
    fi

    # Check available port
    if ss -tulpn | grep -q ":$SERVICE_PORT "; then
        error "Port $SERVICE_PORT is already in use"
        info "Change SERVICE_PORT or stop the conflicting service"
        exit 1
    fi

    # Check disk space (need at least 500MB)
    local available_space
    available_space=$(df / | tail -1 | awk '{print $4}')
    if [[ $available_space -lt 512000 ]]; then
        warning "Low disk space (less than 500MB available)"
        info "Consider freeing up disk space before continuing"
    fi

    success "Requirements check passed"
}

# Install Node.js and npm
install_nodejs() {
    header "📦 Installing Node.js"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would install Node.js LTS"
        return 0
    fi

    # Check if Node.js is already installed with correct version
    if command -v node >/dev/null 2>&1; then
        local node_version
        node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ $node_version -ge 16 ]]; then
            success "Node.js already installed (version $(node --version))"
            return 0
        fi
    fi

    info "Installing Node.js LTS..."

    # Install Node.js from NodeSource repository
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        apt-get install -y nodejs
    else
        error "curl not available for Node.js installation"
        exit 1
    fi

    # Verify installation
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        success "Node.js $(node --version) and npm $(npm --version) installed"
    else
        error "Node.js installation failed"
        exit 1
    fi
}

# Create service user
create_service_user() {
    header "👤 Creating Service User"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would create user $SERVICE_USER"
        return 0
    fi

    if id "$SERVICE_USER" >/dev/null 2>&1; then
        success "User $SERVICE_USER already exists"
        return 0
    fi

    info "Creating user $SERVICE_USER..."

    # Create system user for dashboard service
    useradd -r -s /bin/false -d "$APP_DIR" -c "Pi Gateway Dashboard" "$SERVICE_USER"

    success "Service user $SERVICE_USER created"
}

# Setup application
setup_application() {
    header "⚙️  Setting Up Dashboard Application"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would setup application in $APP_DIR"
        return 0
    fi

    info "Creating application directory..."
    mkdir -p "$APP_DIR"

    # Create a simple Express.js dashboard application
    cat > "$APP_DIR/package.json" << 'EOF'
{
  "name": "pi-gateway-dashboard",
  "version": "1.0.0",
  "description": "Pi Gateway Web Dashboard",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "body-parser": "^1.20.2",
    "ejs": "^3.1.9",
    "bcrypt": "^5.1.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

    # Create main server file
    cat > "$APP_DIR/server.js" << 'EOF'
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const bcrypt = require('bcrypt');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Configuration
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static(path.join(__dirname, 'public')));
app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

// Session management
app.use(session({
    secret: process.env.SESSION_SECRET || 'pi-gateway-secret',
    resave: false,
    saveUninitialized: false,
    cookie: { secure: false, maxAge: 3600000 } // 1 hour
}));

// Simple authentication middleware
const requireAuth = (req, res, next) => {
    if (req.session.authenticated) {
        next();
    } else {
        res.redirect('/login');
    }
};

// Routes
app.get('/', requireAuth, (req, res) => {
    try {
        const systemInfo = {
            hostname: execSync('hostname').toString().trim(),
            uptime: execSync('uptime -p').toString().trim(),
            temperature: execSync('vcgencmd measure_temp 2>/dev/null || echo "temp=N/A"').toString().trim(),
            memory: execSync('free -h | grep Mem').toString().trim(),
            disk: execSync('df -h / | tail -1').toString().trim()
        };
        res.render('dashboard', { systemInfo });
    } catch (error) {
        res.render('dashboard', { systemInfo: {}, error: 'Unable to fetch system information' });
    }
});

app.get('/login', (req, res) => {
    res.render('login', { error: null });
});

app.post('/login', async (req, res) => {
    const { username, password } = req.body;

    // Simple authentication (in production, use proper user management)
    if (username === 'admin' && password === 'admin') {
        req.session.authenticated = true;
        res.redirect('/');
    } else {
        res.render('login', { error: 'Invalid credentials' });
    }
});

app.get('/logout', (req, res) => {
    req.session.destroy();
    res.redirect('/login');
});

// API endpoints
app.get('/api/status', requireAuth, (req, res) => {
    try {
        const status = {
            services: {
                ssh: execSync('systemctl is-active ssh 2>/dev/null || echo "inactive"').toString().trim(),
                wireguard: execSync('systemctl is-active wg-quick@wg0 2>/dev/null || echo "inactive"').toString().trim(),
                ufw: execSync('systemctl is-active ufw 2>/dev/null || echo "inactive"').toString().trim()
            },
            system: {
                load: execSync('uptime | awk -F"load average:" "{print $2}"').toString().trim(),
                memory: execSync('free | grep Mem | awk "{printf \"%.1f\", $3/$2 * 100.0}"').toString().trim(),
                disk: execSync('df / | tail -1 | awk "{print $5}"').toString().trim()
            }
        };
        res.json(status);
    } catch (error) {
        res.status(500).json({ error: 'Unable to fetch status' });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Pi Gateway Dashboard running on port ${PORT}`);
});
EOF

    # Create views directory and templates
    mkdir -p "$APP_DIR/views"

    # Create dashboard template
    cat > "$APP_DIR/views/dashboard.ejs" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pi Gateway Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .card { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .status-item { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #eee; }
        .status-active { color: #27ae60; }
        .status-inactive { color: #e74c3c; }
        .logout { float: right; color: #ecf0f1; text-decoration: none; }
        .logout:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Pi Gateway Dashboard</h1>
            <a href="/logout" class="logout">Logout</a>
        </div>

        <div class="status-grid">
            <div class="card">
                <h3>System Information</h3>
                <% if (systemInfo.hostname) { %>
                    <div class="status-item">
                        <span>Hostname:</span>
                        <span><%= systemInfo.hostname %></span>
                    </div>
                    <div class="status-item">
                        <span>Uptime:</span>
                        <span><%= systemInfo.uptime %></span>
                    </div>
                    <div class="status-item">
                        <span>Temperature:</span>
                        <span><%= systemInfo.temperature %></span>
                    </div>
                <% } else { %>
                    <p>System information unavailable</p>
                <% } %>
            </div>

            <div class="card">
                <h3>Quick Actions</h3>
                <button onclick="location.reload()">Refresh Status</button>
                <button onclick="window.open('/api/status', '_blank')">View API</button>
            </div>
        </div>

        <div class="card">
            <h3>Real-time Status</h3>
            <div id="status-container">Loading...</div>
        </div>
    </div>

    <script>
        function updateStatus() {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    const container = document.getElementById('status-container');
                    container.innerHTML = `
                        <div class="status-grid">
                            <div>
                                <h4>Services</h4>
                                <div class="status-item">
                                    <span>SSH:</span>
                                    <span class="${data.services.ssh === 'active' ? 'status-active' : 'status-inactive'}">
                                        ${data.services.ssh}
                                    </span>
                                </div>
                                <div class="status-item">
                                    <span>WireGuard VPN:</span>
                                    <span class="${data.services.wireguard === 'active' ? 'status-active' : 'status-inactive'}">
                                        ${data.services.wireguard}
                                    </span>
                                </div>
                                <div class="status-item">
                                    <span>Firewall:</span>
                                    <span class="${data.services.ufw === 'active' ? 'status-active' : 'status-inactive'}">
                                        ${data.services.ufw}
                                    </span>
                                </div>
                            </div>
                            <div>
                                <h4>System Resources</h4>
                                <div class="status-item">
                                    <span>Load Average:</span>
                                    <span>${data.system.load}</span>
                                </div>
                                <div class="status-item">
                                    <span>Memory Usage:</span>
                                    <span>${data.system.memory}%</span>
                                </div>
                                <div class="status-item">
                                    <span>Disk Usage:</span>
                                    <span>${data.system.disk}</span>
                                </div>
                            </div>
                        </div>
                    `;
                })
                .catch(error => {
                    document.getElementById('status-container').innerHTML = 'Error loading status';
                });
        }

        // Update status every 30 seconds
        updateStatus();
        setInterval(updateStatus, 30000);
    </script>
</body>
</html>
EOF

    # Create login template
    cat > "$APP_DIR/views/login.ejs" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pi Gateway Dashboard - Login</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #34495e; display: flex; justify-content: center; align-items: center; height: 100vh; }
        .login-container { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 400px; width: 100%; }
        .login-header { text-align: center; margin-bottom: 30px; color: #2c3e50; }
        .form-group { margin-bottom: 20px; }
        label { display: block; margin-bottom: 5px; color: #555; }
        input[type="text"], input[type="password"] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        button { width: 100%; padding: 12px; background: #3498db; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        button:hover { background: #2980b9; }
        .error { color: #e74c3c; text-align: center; margin-bottom: 20px; }
        .info { color: #7f8c8d; text-align: center; margin-top: 20px; font-size: 14px; }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="login-header">
            <h2>Pi Gateway Dashboard</h2>
        </div>

        <% if (error) { %>
            <div class="error"><%= error %></div>
        <% } %>

        <form method="POST" action="/login">
            <div class="form-group">
                <label for="username">Username:</label>
                <input type="text" id="username" name="username" required>
            </div>

            <div class="form-group">
                <label for="password">Password:</label>
                <input type="password" id="password" name="password" required>
            </div>

            <button type="submit">Login</button>
        </form>

        <div class="info">
            Default credentials: admin / admin
        </div>
    </div>
</body>
</html>
EOF

    # Install npm dependencies
    info "Installing application dependencies..."
    cd "$APP_DIR"
    npm install --production

    # Set proper ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"

    success "Dashboard application setup completed"
}

# Create configuration
create_configuration() {
    header "📄 Creating Configuration"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would create configuration at $CONFIG_FILE"
        return 0
    fi

    cat > "$CONFIG_FILE" << EOF
# Pi Gateway Dashboard Configuration

# Server settings
PORT=$SERVICE_PORT
BIND_ADDRESS=0.0.0.0

# Security
SESSION_SECRET=$(openssl rand -base64 32)
ENABLE_AUTH=true

# Logging
LOG_LEVEL=info
LOG_FILE=$LOG_FILE

# Features
REFRESH_INTERVAL=30
ENABLE_API=true
EOF

    chmod 644 "$CONFIG_FILE"

    success "Configuration created at $CONFIG_FILE"
}

# Create systemd service
create_systemd_service() {
    header "⚙️  Creating Systemd Service"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would create systemd service"
        return 0
    fi

    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Pi Gateway Dashboard
Documentation=https://github.com/vnykmshr/pi-gateway
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_DIR
Environment=NODE_ENV=production
EnvironmentFile=$CONFIG_FILE
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    # Create log file
    touch "$LOG_FILE"
    chown "$SERVICE_USER:$SERVICE_USER" "$LOG_FILE"

    success "Systemd service created"
}

# Configure firewall
configure_firewall() {
    header "🔥 Configuring Firewall"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would configure firewall for port $SERVICE_PORT"
        return 0
    fi

    if command -v ufw >/dev/null 2>&1; then
        info "Adding firewall rule for port $SERVICE_PORT..."
        ufw allow "$SERVICE_PORT"/tcp comment "Pi Gateway Dashboard"
        success "Firewall configured"
    else
        warning "UFW not available - manual firewall configuration may be needed"
    fi
}

# Enable and start service
enable_service() {
    header "🚀 Starting Dashboard Service"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY-RUN: Would enable and start $SERVICE_NAME"
        return 0
    fi

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    # Wait a moment and check status
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        success "$SERVICE_NAME started successfully"
    else
        error "$SERVICE_NAME failed to start"
        info "Check logs: journalctl -u $SERVICE_NAME"
        exit 1
    fi
}

# Print completion message
print_completion() {
    header "🎉 Installation Complete"

    local hostname
    hostname=$(hostname)

    success "Pi Gateway Dashboard installed successfully!"
    echo
    info "Dashboard is now available at:"
    echo "  • Local:  http://localhost:$SERVICE_PORT"
    echo "  • Network: http://$hostname:$SERVICE_PORT"
    echo "  • External: http://your-external-ip:$SERVICE_PORT"
    echo
    info "Default login credentials:"
    echo "  • Username: admin"
    echo "  • Password: admin"
    echo
    warning "Change default password after first login!"
    echo
    info "Service management:"
    echo "  • Status:  systemctl status $SERVICE_NAME"
    echo "  • Logs:    journalctl -u $SERVICE_NAME -f"
    echo "  • Restart: systemctl restart $SERVICE_NAME"
    echo
}

# Main execution
main() {
    header "🚀 Pi Gateway Dashboard Extension Setup"

    info "Extension: $EXTENSION_NAME v$EXTENSION_VERSION"
    info "Service: $SERVICE_NAME"
    info "Port: $SERVICE_PORT"
    echo

    check_requirements
    install_nodejs
    create_service_user
    setup_application
    create_configuration
    create_systemd_service
    configure_firewall
    enable_service
    print_completion
}

# Show help
show_help() {
    echo "Pi Gateway Dashboard Extension Setup"
    echo
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --dry-run      Test mode without making changes"
    echo
    echo "Environment Variables:"
    echo "  DRY_RUN=true           Enable dry-run mode"
    echo "  SERVICE_PORT=3000      Custom port (default: 3000)"
    echo "  ALLOW_NON_ROOT=true    Allow running without root"
    echo
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --dry-run)
        export DRY_RUN=true
        main
        ;;
    *)
        main "$@"
        ;;
esac