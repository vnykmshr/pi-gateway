#!/bin/bash
#
# Pi Gateway Status Dashboard
# Web-based real-time status monitoring
#

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly DASHBOARD_DIR="$PROJECT_ROOT/dashboard"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly STATE_DIR="$PROJECT_ROOT/state"
readonly LOG_DIR="$PROJECT_ROOT/logs"
readonly DASHBOARD_CONFIG="$CONFIG_DIR/dashboard.conf"
readonly DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"

# Logging functions
success() { echo -e "  ${GREEN}✓${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

# Initialize dashboard
initialize_dashboard() {
    info "Initializing Pi Gateway status dashboard..."

    # Create required directories
    mkdir -p "$DASHBOARD_DIR" "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR"
    mkdir -p "$DASHBOARD_DIR"/{static,templates,api,data}

    # Create dashboard configuration
    create_dashboard_config

    # Create HTML templates
    create_html_templates

    # Create CSS and JavaScript assets
    create_static_assets

    # Create API endpoints
    create_api_endpoints

    success "Dashboard initialized in: $DASHBOARD_DIR"
}

# Create dashboard configuration
create_dashboard_config() {
    if [[ -f "$DASHBOARD_CONFIG" ]]; then
        return
    fi

    cat > "$DASHBOARD_CONFIG" << 'EOF'
# Pi Gateway Dashboard Configuration

# Server Settings
DASHBOARD_PORT=8080
DASHBOARD_HOST="0.0.0.0"
ENABLE_AUTH=false
USERNAME="admin"
PASSWORD="admin"

# Update Intervals (seconds)
SYSTEM_METRICS_INTERVAL=5
SERVICE_STATUS_INTERVAL=10
NETWORK_STATUS_INTERVAL=15

# Display Settings
SHOW_SYSTEM_INFO=true
SHOW_NETWORK_INFO=true
SHOW_CONTAINER_INFO=true
SHOW_VPN_INFO=true
SHOW_SECURITY_INFO=true

# Alert Thresholds
CPU_WARNING_THRESHOLD=70
CPU_CRITICAL_THRESHOLD=85
MEMORY_WARNING_THRESHOLD=80
MEMORY_CRITICAL_THRESHOLD=90
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=90
TEMP_WARNING_THRESHOLD=70
TEMP_CRITICAL_THRESHOLD=80
EOF

    success "Dashboard configuration created: $DASHBOARD_CONFIG"
}

# Create HTML templates
create_html_templates() {
    # Main dashboard template
    cat > "$DASHBOARD_DIR/templates/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pi Gateway Dashboard</title>
    <link rel="stylesheet" href="/static/dashboard.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🏠</text></svg>">
</head>
<body>
    <header class="header">
        <div class="container">
            <h1 class="logo">🏠 Pi Gateway Dashboard</h1>
            <div class="status-indicator" id="connection-status">
                <span class="dot online"></span>
                <span>Connected</span>
            </div>
        </div>
    </header>

    <main class="main">
        <div class="container">
            <!-- System Overview -->
            <section class="section">
                <h2>System Overview</h2>
                <div class="cards">
                    <div class="card">
                        <h3>System Health</h3>
                        <div id="system-health" class="metric-value">Good</div>
                        <div class="metric-unit">Overall Status</div>
                    </div>
                    <div class="card">
                        <h3>CPU Usage</h3>
                        <div id="cpu-usage" class="metric-value">0%</div>
                        <div class="progress-bar">
                            <div id="cpu-progress" class="progress-fill"></div>
                        </div>
                    </div>
                    <div class="card">
                        <h3>Memory Usage</h3>
                        <div id="memory-usage" class="metric-value">0%</div>
                        <div class="progress-bar">
                            <div id="memory-progress" class="progress-fill"></div>
                        </div>
                    </div>
                    <div class="card">
                        <h3>Temperature</h3>
                        <div id="temperature" class="metric-value">0°C</div>
                        <div class="metric-unit">CPU Temp</div>
                    </div>
                </div>
            </section>

            <!-- Services Status -->
            <section class="section">
                <h2>Services</h2>
                <div class="service-grid" id="services-grid">
                    <!-- Services will be populated by JavaScript -->
                </div>
            </section>

            <!-- Network Status -->
            <section class="section">
                <h2>Network & Connectivity</h2>
                <div class="cards">
                    <div class="card">
                        <h3>VPN Status</h3>
                        <div id="vpn-status" class="status-badge">Unknown</div>
                        <div id="vpn-clients" class="metric-unit">0 clients</div>
                    </div>
                    <div class="card">
                        <h3>External IP</h3>
                        <div id="external-ip" class="metric-value">Checking...</div>
                        <div class="metric-unit">Public Address</div>
                    </div>
                    <div class="card">
                        <h3>DDNS Status</h3>
                        <div id="ddns-status" class="status-badge">Unknown</div>
                        <div id="ddns-domain" class="metric-unit">No domain</div>
                    </div>
                    <div class="card">
                        <h3>Network Traffic</h3>
                        <div id="network-traffic" class="metric-value">0 MB/s</div>
                        <div class="metric-unit">Up/Down</div>
                    </div>
                </div>
            </section>

            <!-- Container Services -->
            <section class="section" id="containers-section" style="display: none;">
                <h2>Container Services</h2>
                <div class="service-grid" id="containers-grid">
                    <!-- Containers will be populated by JavaScript -->
                </div>
            </section>

            <!-- Recent Events -->
            <section class="section">
                <h2>Recent Events</h2>
                <div class="events-container">
                    <div id="recent-events" class="events-list">
                        <!-- Events will be populated by JavaScript -->
                    </div>
                </div>
            </section>
        </div>
    </main>

    <footer class="footer">
        <div class="container">
            <p>&copy; 2024 Pi Gateway. Last updated: <span id="last-updated">Never</span></p>
        </div>
    </footer>

    <script src="/static/dashboard.js"></script>
</body>
</html>
EOF

    success "HTML template created"
}

# Create CSS styles
create_static_assets() {
    # CSS Styles
    cat > "$DASHBOARD_DIR/static/dashboard.css" << 'EOF'
/* Pi Gateway Dashboard Styles */
:root {
    --primary-color: #2563eb;
    --success-color: #10b981;
    --warning-color: #f59e0b;
    --danger-color: #ef4444;
    --background-color: #f8fafc;
    --card-background: #ffffff;
    --text-primary: #1f2937;
    --text-secondary: #6b7280;
    --border-color: #e5e7eb;
    --border-radius: 8px;
    --shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background-color: var(--background-color);
    color: var(--text-primary);
    line-height: 1.6;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 1rem;
}

/* Header */
.header {
    background: var(--card-background);
    border-bottom: 1px solid var(--border-color);
    padding: 1rem 0;
    position: sticky;
    top: 0;
    z-index: 100;
}

.header .container {
    display: flex;
    justify-content: between;
    align-items: center;
    gap: 2rem;
}

.logo {
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--primary-color);
}

.status-indicator {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-left: auto;
}

.dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
}

.dot.online { background-color: var(--success-color); }
.dot.offline { background-color: var(--danger-color); }
.dot.warning { background-color: var(--warning-color); }

/* Main Content */
.main {
    padding: 2rem 0;
}

.section {
    margin-bottom: 3rem;
}

.section h2 {
    font-size: 1.25rem;
    font-weight: 600;
    margin-bottom: 1rem;
    color: var(--text-primary);
}

/* Cards */
.cards {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1rem;
}

.card {
    background: var(--card-background);
    border: 1px solid var(--border-color);
    border-radius: var(--border-radius);
    padding: 1.5rem;
    box-shadow: var(--shadow);
    transition: transform 0.2s, box-shadow 0.2s;
}

.card:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px 0 rgba(0, 0, 0, 0.15);
}

.card h3 {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
}

.metric-value {
    font-size: 2rem;
    font-weight: 700;
    color: var(--text-primary);
    margin-bottom: 0.25rem;
}

.metric-unit {
    font-size: 0.875rem;
    color: var(--text-secondary);
}

/* Progress Bars */
.progress-bar {
    width: 100%;
    height: 8px;
    background-color: var(--border-color);
    border-radius: 4px;
    overflow: hidden;
    margin-top: 0.5rem;
}

.progress-fill {
    height: 100%;
    background-color: var(--success-color);
    transition: width 0.3s ease;
}

.progress-fill.warning { background-color: var(--warning-color); }
.progress-fill.danger { background-color: var(--danger-color); }

/* Status Badges */
.status-badge {
    display: inline-block;
    padding: 0.25rem 0.75rem;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.05em;
}

.status-badge.online {
    background-color: #dcfce7;
    color: #166534;
}

.status-badge.offline {
    background-color: #fee2e2;
    color: #991b1b;
}

.status-badge.warning {
    background-color: #fef3c7;
    color: #92400e;
}

/* Service Grid */
.service-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 1rem;
}

.service-item {
    background: var(--card-background);
    border: 1px solid var(--border-color);
    border-radius: var(--border-radius);
    padding: 1rem;
    display: flex;
    align-items: center;
    gap: 0.75rem;
}

.service-icon {
    width: 40px;
    height: 40px;
    border-radius: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.25rem;
}

.service-icon.online { background-color: #dcfce7; }
.service-icon.offline { background-color: #fee2e2; }
.service-icon.warning { background-color: #fef3c7; }

.service-info h4 {
    font-size: 0.875rem;
    font-weight: 600;
    margin-bottom: 0.25rem;
}

.service-info p {
    font-size: 0.75rem;
    color: var(--text-secondary);
}

/* Events */
.events-container {
    background: var(--card-background);
    border: 1px solid var(--border-color);
    border-radius: var(--border-radius);
    overflow: hidden;
}

.events-list {
    max-height: 300px;
    overflow-y: auto;
}

.event-item {
    padding: 0.75rem 1rem;
    border-bottom: 1px solid var(--border-color);
    display: flex;
    align-items: center;
    gap: 0.75rem;
}

.event-item:last-child {
    border-bottom: none;
}

.event-time {
    font-size: 0.75rem;
    color: var(--text-secondary);
    min-width: 80px;
}

.event-message {
    font-size: 0.875rem;
    flex: 1;
}

/* Footer */
.footer {
    background: var(--card-background);
    border-top: 1px solid var(--border-color);
    padding: 1rem 0;
    margin-top: 2rem;
    text-align: center;
    color: var(--text-secondary);
    font-size: 0.875rem;
}

/* Responsive Design */
@media (max-width: 768px) {
    .cards {
        grid-template-columns: 1fr;
    }

    .header .container {
        flex-direction: column;
        gap: 1rem;
    }

    .metric-value {
        font-size: 1.5rem;
    }
}

/* Loading States */
.loading {
    opacity: 0.6;
    pointer-events: none;
}

/* Animations */
@keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
}

.pulse {
    animation: pulse 2s infinite;
}
EOF

    # JavaScript functionality
    cat > "$DASHBOARD_DIR/static/dashboard.js" << 'EOF'
// Pi Gateway Dashboard JavaScript

class Dashboard {
    constructor() {
        this.wsConnection = null;
        this.updateIntervals = {};
        this.lastUpdate = null;

        this.init();
    }

    init() {
        this.setupEventListeners();
        this.startDataUpdates();
        this.updateLastUpdated();

        // Try to establish WebSocket connection
        this.connectWebSocket();
    }

    setupEventListeners() {
        // Connection status updates
        window.addEventListener('online', () => this.updateConnectionStatus(true));
        window.addEventListener('offline', () => this.updateConnectionStatus(false));

        // Page visibility changes
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                this.pauseUpdates();
            } else {
                this.resumeUpdates();
            }
        });
    }

    connectWebSocket() {
        if ('WebSocket' in window) {
            try {
                this.wsConnection = new WebSocket(`ws://${window.location.host}/ws`);

                this.wsConnection.onopen = () => {
                    console.log('WebSocket connected');
                    this.updateConnectionStatus(true);
                };

                this.wsConnection.onmessage = (event) => {
                    const data = JSON.parse(event.data);
                    this.handleRealtimeUpdate(data);
                };

                this.wsConnection.onclose = () => {
                    console.log('WebSocket disconnected');
                    this.updateConnectionStatus(false);
                    // Reconnect after 5 seconds
                    setTimeout(() => this.connectWebSocket(), 5000);
                };
            } catch (error) {
                console.warn('WebSocket not available, using polling');
            }
        }
    }

    startDataUpdates() {
        // System metrics every 5 seconds
        this.updateIntervals.system = setInterval(() => {
            this.updateSystemMetrics();
        }, 5000);

        // Services every 10 seconds
        this.updateIntervals.services = setInterval(() => {
            this.updateServices();
        }, 10000);

        // Network status every 15 seconds
        this.updateIntervals.network = setInterval(() => {
            this.updateNetworkStatus();
        }, 15000);

        // Containers every 30 seconds
        this.updateIntervals.containers = setInterval(() => {
            this.updateContainers();
        }, 30000);

        // Events every 30 seconds
        this.updateIntervals.events = setInterval(() => {
            this.updateEvents();
        }, 30000);

        // Initial updates
        this.updateSystemMetrics();
        this.updateServices();
        this.updateNetworkStatus();
        this.updateContainers();
        this.updateEvents();
    }

    pauseUpdates() {
        Object.values(this.updateIntervals).forEach(interval => {
            clearInterval(interval);
        });
    }

    resumeUpdates() {
        this.startDataUpdates();
    }

    async updateSystemMetrics() {
        try {
            const response = await fetch('/api/system/metrics');
            const data = await response.json();

            // Update CPU usage
            this.updateMetric('cpu-usage', `${data.cpu.usage}%`);
            this.updateProgressBar('cpu-progress', data.cpu.usage);

            // Update memory usage
            this.updateMetric('memory-usage', `${data.memory.usage}%`);
            this.updateProgressBar('memory-progress', data.memory.usage);

            // Update temperature
            this.updateMetric('temperature', `${data.temperature}°C`);

            // Update system health
            this.updateMetric('system-health', data.health.status);

            this.updateLastUpdated();
        } catch (error) {
            console.error('Failed to update system metrics:', error);
        }
    }

    async updateServices() {
        try {
            const response = await fetch('/api/services/status');
            const services = await response.json();

            this.renderServices(services);
        } catch (error) {
            console.error('Failed to update services:', error);
        }
    }

    async updateNetworkStatus() {
        try {
            const response = await fetch('/api/network/status');
            const data = await response.json();

            // Update VPN status
            this.updateStatusBadge('vpn-status', data.vpn.status);
            this.updateMetric('vpn-clients', `${data.vpn.connected_clients} clients`);

            // Update external IP
            this.updateMetric('external-ip', data.external_ip || 'Unknown');

            // Update DDNS status
            this.updateStatusBadge('ddns-status', data.ddns.status);
            this.updateMetric('ddns-domain', data.ddns.domain || 'No domain');

            // Update network traffic
            this.updateMetric('network-traffic', `${data.traffic.up}/${data.traffic.down} MB/s`);
        } catch (error) {
            console.error('Failed to update network status:', error);
        }
    }

    async updateContainers() {
        try {
            const response = await fetch('/api/containers/status');
            const containers = await response.json();

            if (containers.length > 0) {
                document.getElementById('containers-section').style.display = 'block';
                this.renderContainers(containers);
            }
        } catch (error) {
            console.error('Failed to update containers:', error);
        }
    }

    async updateEvents() {
        try {
            const response = await fetch('/api/events/recent');
            const events = await response.json();

            this.renderEvents(events);
        } catch (error) {
            console.error('Failed to update events:', error);
        }
    }

    updateMetric(elementId, value) {
        const element = document.getElementById(elementId);
        if (element) {
            element.textContent = value;
        }
    }

    updateProgressBar(elementId, percentage) {
        const element = document.getElementById(elementId);
        if (element) {
            element.style.width = `${percentage}%`;

            // Update color based on percentage
            element.className = 'progress-fill';
            if (percentage >= 90) {
                element.classList.add('danger');
            } else if (percentage >= 70) {
                element.classList.add('warning');
            }
        }
    }

    updateStatusBadge(elementId, status) {
        const element = document.getElementById(elementId);
        if (element) {
            element.textContent = status;
            element.className = `status-badge ${status.toLowerCase()}`;
        }
    }

    renderServices(services) {
        const container = document.getElementById('services-grid');
        container.innerHTML = '';

        services.forEach(service => {
            const serviceElement = this.createServiceElement(service);
            container.appendChild(serviceElement);
        });
    }

    renderContainers(containers) {
        const container = document.getElementById('containers-grid');
        container.innerHTML = '';

        containers.forEach(container_info => {
            const containerElement = this.createServiceElement(container_info);
            container.appendChild(containerElement);
        });
    }

    createServiceElement(service) {
        const element = document.createElement('div');
        element.className = 'service-item';

        const statusClass = service.status === 'running' ? 'online' :
                          service.status === 'stopped' ? 'offline' : 'warning';

        element.innerHTML = `
            <div class="service-icon ${statusClass}">
                ${this.getServiceIcon(service.name)}
            </div>
            <div class="service-info">
                <h4>${service.name}</h4>
                <p>${service.status}</p>
            </div>
        `;

        return element;
    }

    getServiceIcon(serviceName) {
        const icons = {
            'ssh': '🔐',
            'wireguard': '🔒',
            'docker': '🐳',
            'ufw': '🛡️',
            'homeassistant': '🏠',
            'grafana': '📊',
            'pihole': '🚫',
            'nodered': '🔄',
            'portainer': '🐳'
        };

        return icons[serviceName.toLowerCase()] || '⚙️';
    }

    renderEvents(events) {
        const container = document.getElementById('recent-events');
        container.innerHTML = '';

        if (events.length === 0) {
            container.innerHTML = '<div class="event-item"><span class="event-message">No recent events</span></div>';
            return;
        }

        events.forEach(event => {
            const eventElement = document.createElement('div');
            eventElement.className = 'event-item';
            eventElement.innerHTML = `
                <span class="event-time">${this.formatTime(event.timestamp)}</span>
                <span class="event-message">${event.message}</span>
            `;
            container.appendChild(eventElement);
        });
    }

    formatTime(timestamp) {
        const date = new Date(timestamp);
        return date.toLocaleTimeString();
    }

    updateConnectionStatus(connected) {
        const indicator = document.querySelector('#connection-status .dot');
        const text = document.querySelector('#connection-status span:last-child');

        if (connected) {
            indicator.className = 'dot online';
            text.textContent = 'Connected';
        } else {
            indicator.className = 'dot offline';
            text.textContent = 'Disconnected';
        }
    }

    updateLastUpdated() {
        const element = document.getElementById('last-updated');
        if (element) {
            element.textContent = new Date().toLocaleTimeString();
        }
    }

    handleRealtimeUpdate(data) {
        // Handle real-time updates from WebSocket
        switch (data.type) {
            case 'system_metrics':
                this.updateSystemMetrics();
                break;
            case 'service_status':
                this.updateServices();
                break;
            case 'network_status':
                this.updateNetworkStatus();
                break;
            case 'event':
                this.updateEvents();
                break;
        }
    }
}

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new Dashboard();
});
EOF

    success "Static assets created"
}

# Create API endpoints
create_api_endpoints() {
    mkdir -p "$DASHBOARD_DIR/api"

    # System metrics API
    cat > "$DASHBOARD_DIR/api/system-metrics.sh" << 'EOF'
#!/bin/bash
# System metrics API endpoint

# Get CPU usage
cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d'%' -f1
}

# Get memory usage
memory_usage() {
    free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}'
}

# Get temperature
get_temperature() {
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        echo $((temp / 1000))
    else
        echo "0"
    fi
}

# Generate JSON response
cat << EOF
{
    "cpu": {
        "usage": $(cpu_usage)
    },
    "memory": {
        "usage": $(memory_usage)
    },
    "temperature": $(get_temperature),
    "health": {
        "status": "Good"
    }
}
EOF
EOF

    chmod +x "$DASHBOARD_DIR/api/system-metrics.sh"

    # Service status API
    cat > "$DASHBOARD_DIR/api/service-status.sh" << 'EOF'
#!/bin/bash
# Service status API endpoint

get_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo "running"
    elif systemctl is-enabled --quiet "$service"; then
        echo "stopped"
    else
        echo "disabled"
    fi
}

# Generate JSON response
cat << EOF
[
    {
        "name": "SSH",
        "status": "$(get_service_status ssh)"
    },
    {
        "name": "WireGuard",
        "status": "$(get_service_status wg-quick@wg0)"
    },
    {
        "name": "UFW",
        "status": "$(get_service_status ufw)"
    },
    {
        "name": "Docker",
        "status": "$(get_service_status docker)"
    }
]
EOF
EOF

    chmod +x "$DASHBOARD_DIR/api/service-status.sh"

    success "API endpoints created"
}

# Start dashboard server
start_dashboard() {
    local port="${DASHBOARD_PORT:-8080}"

    info "Starting Pi Gateway dashboard on port $port..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would start dashboard server on port $port"
        return
    fi

    # Check if port is available
    if netstat -tuln | grep -q ":$port "; then
        error "Port $port is already in use"
        return 1
    fi

    # Start simple HTTP server
    cd "$DASHBOARD_DIR"

    # Use Python's built-in server
    if command -v python3 >/dev/null 2>&1; then
        python3 -m http.server "$port" --bind 0.0.0.0 &
        local server_pid=$!
        echo "$server_pid" > "$STATE_DIR/dashboard.pid"

        success "Dashboard started on http://$(hostname -I | awk '{print $1}'):$port"
        info "Process ID: $server_pid"

        # Create systemd service for persistence
        create_systemd_service "$port"
    else
        error "Python3 not available for HTTP server"
        return 1
    fi
}

# Stop dashboard server
stop_dashboard() {
    info "Stopping Pi Gateway dashboard..."

    if [[ -f "$STATE_DIR/dashboard.pid" ]]; then
        local pid
        pid=$(cat "$STATE_DIR/dashboard.pid")
        if kill "$pid" 2>/dev/null; then
            success "Dashboard stopped (PID: $pid)"
        else
            warning "Dashboard process not found"
        fi
        rm -f "$STATE_DIR/dashboard.pid"
    else
        warning "No dashboard PID file found"
    fi

    # Stop systemd service if it exists
    if systemctl is-active --quiet pi-gateway-dashboard; then
        sudo systemctl stop pi-gateway-dashboard
        sudo systemctl disable pi-gateway-dashboard
    fi
}

# Create systemd service
create_systemd_service() {
    local port="$1"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would create systemd service"
        return
    fi

    sudo tee /etc/systemd/system/pi-gateway-dashboard.service > /dev/null << EOF
[Unit]
Description=Pi Gateway Status Dashboard
After=network.target
Wants=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=$DASHBOARD_DIR
ExecStart=/usr/bin/python3 -m http.server $port --bind 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable pi-gateway-dashboard
    sudo systemctl start pi-gateway-dashboard

    success "Systemd service created and started"
}

# Show dashboard status
show_dashboard_status() {
    echo -e "${CYAN}📊 Dashboard Status${NC}"
    echo

    if [[ -f "$STATE_DIR/dashboard.pid" ]]; then
        local pid
        pid=$(cat "$STATE_DIR/dashboard.pid")
        if kill -0 "$pid" 2>/dev/null; then
            success "Dashboard running (PID: $pid)"
            local port
            port=$(netstat -tulpn 2>/dev/null | grep "$pid" | grep -o ':[0-9]*' | head -1 | cut -d':' -f2)
            if [[ -n "$port" ]]; then
                info "URL: http://$(hostname -I | awk '{print $1}'):$port"
            fi
        else
            warning "Dashboard PID file exists but process not running"
        fi
    else
        warning "Dashboard not running"
    fi

    # Check systemd service
    if systemctl is-active --quiet pi-gateway-dashboard; then
        success "Systemd service: Active"
    else
        info "Systemd service: Inactive"
    fi
}

# Show help
show_help() {
    echo "Pi Gateway Status Dashboard"
    echo
    echo "Usage: $(basename "$0") <command> [options]"
    echo
    echo "Commands:"
    echo "  init                 Initialize dashboard files"
    echo "  start                Start dashboard server"
    echo "  stop                 Stop dashboard server"
    echo "  restart              Restart dashboard server"
    echo "  status               Show dashboard status"
    echo "  help                 Show this help message"
    echo
    echo "Options:"
    echo "  --port PORT          Dashboard port (default: 8080)"
    echo "  --dry-run           Show what would be done without making changes"
    echo
    echo "Examples:"
    echo "  $(basename "$0") init"
    echo "  $(basename "$0") start --port 9090"
    echo "  $(basename "$0") status"
    echo
}

# Main execution
main() {
    local command="${1:-}"

    # Handle global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                export DASHBOARD_PORT="$2"
                shift 2
                ;;
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    case $command in
        init)
            initialize_dashboard
            ;;
        start)
            initialize_dashboard
            start_dashboard
            ;;
        stop)
            stop_dashboard
            ;;
        restart)
            stop_dashboard
            sleep 2
            start_dashboard
            ;;
        status)
            show_dashboard_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -n "$command" ]]; then
                error "Unknown command: $command"
            else
                error "No command specified"
            fi
            echo "Use '$(basename "$0") help' for available commands"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
