#!/bin/bash
#
# Pi Gateway - Network Mocking Functions
# Mock network connectivity and DNS resolution
#

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Mock network configuration
MOCK_NETWORK_INTERFACES="${MOCK_NETWORK_INTERFACES:-eth0,wlan0}"
MOCK_INTERNET_CONNECTIVITY="${MOCK_INTERNET_CONNECTIVITY:-true}"
MOCK_DNS_RESOLUTION="${MOCK_DNS_RESOLUTION:-true}"
MOCK_NETWORK_SPEED="${MOCK_NETWORK_SPEED:-100}"

# Mock ping command for connectivity testing
mock_ping() {
    local target="$1"
    local count="${2:-1}"

    if is_mocked "network"; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} ping -c $count $target"

        if [[ "$MOCK_INTERNET_CONNECTIVITY" == "true" ]]; then
            # Simulate successful ping
            echo "PING $target (8.8.8.8): 56 data bytes"
            for ((i=1; i<=count; i++)); do
                echo "64 bytes from $target (8.8.8.8): icmp_seq=$i time=10.${RANDOM:0:3} ms"
                sleep 0.1
            done
            echo "--- $target ping statistics ---"
            echo "$count packets transmitted, $count packets received, 0.0% packet loss"
            return 0
        else
            echo "ping: cannot resolve $target: Name or service not known"
            return 1
        fi
    fi

    # Fall back to real ping
    ping -c "$count" -W 5 "$target"
}

# Mock nslookup for DNS resolution testing
mock_nslookup() {
    local target="$1"

    if is_mocked "network"; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} nslookup $target"

        if [[ "$MOCK_DNS_RESOLUTION" == "true" ]]; then
            # Simulate successful DNS resolution
            cat << EOF
Server:     8.8.8.8
Address:    8.8.8.8#53

Non-authoritative answer:
Name:   $target
Address: 172.217.164.78
EOF
            return 0
        else
            echo "** server can't find $target: NXDOMAIN"
            return 1
        fi
    fi

    # Fall back to real nslookup
    nslookup "$target"
}

# Mock network interface detection
mock_network_interfaces() {
    if is_mocked "network"; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} Network interfaces simulated"

        # Create mock ip link output
        local interface_count=1
        IFS=',' read -ra interfaces <<< "$MOCK_NETWORK_INTERFACES"

        for interface in "${interfaces[@]}"; do
            echo "$interface_count: $interface: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000"
            echo "    link/ether 02:42:ac:11:00:0$interface_count brd ff:ff:ff:ff:ff:ff"
            ((interface_count++))
        done
        return 0
    fi

    # Fall back to real interface detection
    ip link show | grep -E '^[0-9]+:'
}

# Mock network speed test
mock_network_speed_test() {
    if is_mocked "network"; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} Network speed test: ${MOCK_NETWORK_SPEED}Mbps (simulated)"

        # Simulate speed test output
        echo "Testing download speed..."
        sleep 1
        echo "Download: ${MOCK_NETWORK_SPEED}.${RANDOM:0:2} Mbps"
        echo "Testing upload speed..."
        sleep 1
        echo "Upload: $((MOCK_NETWORK_SPEED / 2)).${RANDOM:0:2} Mbps"
        return 0
    fi

    echo "Real network speed test not implemented"
    return 1
}

# Mock curl connectivity test
mock_curl() {
    local url="$1"
    shift
    local args=("$@")

    if is_mocked "network"; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} curl $url ${args[*]}"

        if [[ "$MOCK_INTERNET_CONNECTIVITY" == "true" ]]; then
            # Simulate successful HTTP response
            echo "HTTP/1.1 200 OK"
            echo "Date: $(date -R)"
            echo "Server: mock-server/1.0"
            echo "Content-Type: text/html"
            echo "Content-Length: 1024"
            echo ""
            echo "<html><head><title>Mock Response</title></head><body>Mock content from $url</body></html>"
            return 0
        else
            echo "curl: (6) Could not resolve host: $url"
            return 6
        fi
    fi

    # Fall back to real curl
    curl "$url" "${args[@]}"
}

# Mock wget connectivity test
mock_wget() {
    local url="$1"
    shift
    local args=("$@")

    if is_mocked "network"; then
        echo -e "  ${MOCK_COLOR}[MOCK]${NC} wget $url ${args[*]}"

        if [[ "$MOCK_INTERNET_CONNECTIVITY" == "true" ]]; then
            # Simulate successful download
            echo "Resolving $url..."
            echo "Connecting to $url... connected."
            echo "HTTP request sent, awaiting response... 200 OK"
            echo "Length: 1024 (1.0K) [text/html]"
            echo "Saving to: 'index.html'"
            echo "100%[===================>] 1.0K  --.-KB/s    in 0s"
            return 0
        else
            echo "wget: unable to resolve host address '$url'"
            return 1
        fi
    fi

    # Fall back to real wget
    wget "$url" "${args[@]}"
}

# Set up mock network environment
setup_mock_network() {
    if is_mocked "network"; then
        echo -e "${MOCK_COLOR}🌐 Setting up mock network environment${NC}"
        echo -e "${MOCK_COLOR}   → Interfaces: $MOCK_NETWORK_INTERFACES${NC}"
        echo -e "${MOCK_COLOR}   → Internet connectivity: $MOCK_INTERNET_CONNECTIVITY${NC}"
        echo -e "${MOCK_COLOR}   → DNS resolution: $MOCK_DNS_RESOLUTION${NC}"
        echo -e "${MOCK_COLOR}   → Network speed: ${MOCK_NETWORK_SPEED}Mbps${NC}"
        echo

        # Create command aliases for mocking
        alias ping='mock_ping'
        alias nslookup='mock_nslookup'
        alias curl='mock_curl'
        alias wget='mock_wget'

        return 0
    fi
}

# Cleanup mock network environment
cleanup_mock_network() {
    if is_mocked "network"; then
        unalias ping 2>/dev/null || true
        unalias nslookup 2>/dev/null || true
        unalias curl 2>/dev/null || true
        unalias wget 2>/dev/null || true
    fi
}

# Validate mock network setup
validate_mock_network() {
    if ! is_mocked "network"; then
        return 0
    fi

    echo -e "${MOCK_COLOR}🔍 Validating mock network setup${NC}"

    local validation_passed=true

    # Test connectivity
    if mock_ping "8.8.8.8" 1 >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Mock connectivity test passed"
    else
        echo -e "  ${RED}✗${NC} Mock connectivity test failed"
        validation_passed=false
    fi

    # Test DNS resolution
    if mock_nslookup "google.com" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Mock DNS resolution test passed"
    else
        echo -e "  ${RED}✗${NC} Mock DNS resolution test failed"
        validation_passed=false
    fi

    # Test interfaces
    local interface_count
    interface_count=$(mock_network_interfaces | wc -l)
    if [[ $interface_count -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Mock network interfaces: $interface_count found"
    else
        echo -e "  ${RED}✗${NC} No mock network interfaces found"
        validation_passed=false
    fi

    if [[ "$validation_passed" == "true" ]]; then
        echo -e "${MOCK_COLOR}✅ Mock network validation passed${NC}"
        return 0
    else
        echo -e "${MOCK_COLOR}❌ Mock network validation failed${NC}"
        return 1
    fi
}

# Export mock functions
export -f mock_ping
export -f mock_nslookup
export -f mock_network_interfaces
export -f mock_network_speed_test
export -f mock_curl
export -f mock_wget
export -f setup_mock_network
export -f cleanup_mock_network
export -f validate_mock_network
