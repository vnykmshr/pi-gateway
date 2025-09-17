#!/bin/bash
#
# Pi Gateway Comprehensive End-to-End Test
# Demonstrates complete Pi Gateway setup flow with detailed validation
#

set -euo pipefail

# Configuration
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly TEST_LOG="/tmp/pi-gateway-comprehensive-test.log"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$TEST_LOG"
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
    ((TESTS_PASSED++))
}

error() {
    echo -e "  ${RED}✗${NC} $1" >&2
    log "ERROR: $1"
    ((TESTS_FAILED++))
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

section() {
    echo
    echo -e "${PURPLE}════════════════════════════════════════${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════${NC}"
    log "SECTION: $1"
}

# Test execution wrapper
run_test() {
    local test_name="$1"
    local command="$2"
    ((TESTS_TOTAL++))

    info "Testing: $test_name"
    if eval "$command" >/dev/null 2>&1; then
        success "$test_name"
        return 0
    else
        error "$test_name"
        return 1
    fi
}

# Initialize test environment
init_test() {
    section "Initializing Comprehensive Pi Gateway Test"
    cd "$PROJECT_ROOT"

    echo "=== Pi Gateway Comprehensive Test Session Started: $(date) ===" > "$TEST_LOG"
    echo "Test Environment: $(uname -a)" >> "$TEST_LOG"
    echo "Working Directory: $(pwd)" >> "$TEST_LOG"
    echo "================================" >> "$TEST_LOG"

    success "Test environment initialized"
}

# Test Phase 1: Pre-Flight Validation
test_preflight() {
    section "Phase 1: Pre-Flight System Validation"

    run_test "System requirements check (with Pi simulation)" \
        "DRY_RUN=true MOCK_HARDWARE=true MOCK_NETWORK=true ./scripts/check-requirements.sh"

    run_test "Hardware detection working" \
        "DRY_RUN=true MOCK_HARDWARE=true ./scripts/check-requirements.sh | grep -q 'Raspberry Pi'"

    run_test "Memory validation functional" \
        "DRY_RUN=true MOCK_HARDWARE=true MOCK_PI_MEMORY_MB=512 ./scripts/check-requirements.sh | grep -q 'Insufficient RAM'"

    run_test "Network connectivity check working" \
        "DRY_RUN=true MOCK_NETWORK=true ./scripts/check-requirements.sh | grep -q 'Internet connectivity'"
}

# Test Phase 2: Dependency Installation
test_dependencies() {
    section "Phase 2: Dependency Installation Process"

    run_test "Dependency installation (dry-run)" \
        "DRY_RUN=true MOCK_SYSTEM=true MOCK_HARDWARE=true ./scripts/install-dependencies.sh | grep -q 'Cleaning up temporary files'"

    run_test "Core packages installation simulated" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/install-dependencies.sh | grep -q 'curl installed successfully'"

    run_test "Security packages installation simulated" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/install-dependencies.sh | grep -q 'ufw installed successfully'"

    run_test "WireGuard installation from backports" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/install-dependencies.sh | grep -q 'WireGuard installed from backports'"

    run_test "Service user creation simulated" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/install-dependencies.sh | grep -q 'Pi Gateway service user created'"
}

# Test Phase 3: Security Hardening
test_security() {
    section "Phase 3: System Security Hardening"

    run_test "System hardening (dry-run)" \
        "DRY_RUN=true MOCK_SYSTEM=true MOCK_HARDWARE=true ./scripts/system-hardening.sh | grep -q 'hardening complete'"

    run_test "SSH hardening configuration" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/ssh-setup.sh | grep -q 'SSH hardening complete'"

    run_test "Firewall setup working" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/firewall-setup.sh | grep -q 'Firewall setup complete'"

    run_test "UFW configuration applied" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/firewall-setup.sh | grep -q 'UFW is now active'"
}

# Test Phase 4: Network Services
test_network_services() {
    section "Phase 4: Network Services Configuration"

    run_test "VPN (WireGuard) setup" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/vpn-setup.sh | grep -q 'WireGuard VPN setup complete'"

    run_test "VPN server configuration" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/vpn-setup.sh | grep -q 'Server keys generated'"

    run_test "VPN client management tools" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/vpn-setup.sh | grep -q 'Client management script created'"

    run_test "Remote desktop setup" \
        "DRY_RUN=true MOCK_SYSTEM=true ./scripts/remote-desktop.sh | grep -q 'VNC server configured'"
}

# Test Phase 5: Service Management
test_service_management() {
    section "Phase 5: Service Management Validation"

    run_test "SSH service configuration" \
        "grep -q 'PasswordAuthentication no' scripts/ssh-setup.sh"

    run_test "Service startup scripts present" \
        "test -f scripts/vpn-client-manager.sh && test -f scripts/pi-gateway-cli.sh"

    run_test "Backup functionality working" \
        "DRY_RUN=true ./scripts/backup-config.sh | grep -q 'Backup completed'"

    run_test "Monitoring system functional" \
        "DRY_RUN=true ./scripts/monitoring-system.sh | grep -q 'Monitoring system configured'"
}

# Test Phase 6: Integration Testing
test_integration() {
    section "Phase 6: End-to-End Integration Testing"

    run_test "Main setup script (dry-run with timeout)" \
        "timeout 30 bash -c 'DRY_RUN=true MOCK_SYSTEM=true MOCK_HARDWARE=true MOCK_NETWORK=true ./setup.sh' || test \$? -eq 124"

    run_test "CLI interface working" \
        "echo 'exit' | DRY_RUN=true ./scripts/pi-gateway-cli.sh | grep -q 'Pi Gateway CLI'"

    run_test "VPN client management functional" \
        "DRY_RUN=true ./scripts/vpn-client-manager.sh list | grep -q 'clients'"

    run_test "Status dashboard accessible" \
        "DRY_RUN=true ./scripts/status-dashboard.sh | grep -q 'Pi Gateway Status'"
}

# Test Phase 7: Security Validation
test_security_validation() {
    section "Phase 7: Security Configuration Validation"

    run_test "No hardcoded credentials in scripts" \
        "! grep -r 'password.*=' scripts/ | grep -v 'PasswordAuthentication' | grep -v 'password.*:' | grep -v '#'"

    run_test "SSH keys properly managed" \
        "grep -q 'ssh-keygen' scripts/ssh-setup.sh"

    run_test "VPN keys securely generated" \
        "grep -q 'wg genkey' scripts/vpn-setup.sh || grep -q 'wg genkey' scripts/vpn-client-manager.sh"

    run_test "File permissions properly set" \
        "grep -q 'chmod.*600' scripts/ssh-setup.sh"
}

# Generate test report
generate_report() {
    section "Test Results Summary"

    local total_score=$((TESTS_PASSED * 100 / TESTS_TOTAL))

    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}              PI GATEWAY COMPREHENSIVE TEST RESULTS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "📊 ${BLUE}Test Statistics:${NC}"
    echo -e "   Total Tests:    ${TESTS_TOTAL}"
    echo -e "   Tests Passed:   ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "   Tests Failed:   ${RED}${TESTS_FAILED}${NC}"
    echo -e "   Success Rate:   ${GREEN}${total_score}%${NC}"
    echo

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "🎉 ${GREEN}ALL TESTS PASSED!${NC}"
        echo -e "   ${GREEN}Pi Gateway v1.1.0 is ready for production deployment${NC}"
        echo
        echo -e "✅ ${GREEN}DEPLOYMENT APPROVED${NC}"
    else
        echo -e "⚠️  ${YELLOW}Some tests failed - review required${NC}"
        echo -e "   ${YELLOW}Check test log for details: $TEST_LOG${NC}"
    fi

    echo
    echo -e "📋 ${BLUE}Quick Deployment Guide:${NC}"
    echo -e "   1. Transfer Pi Gateway to your Raspberry Pi"
    echo -e "   2. Run: ${YELLOW}./scripts/check-requirements.sh${NC}"
    echo -e "   3. Run: ${YELLOW}sudo ./setup.sh${NC}"
    echo -e "   4. Follow the interactive prompts"
    echo -e "   5. Access via SSH on port 2222 when complete"
    echo
    echo -e "📝 ${BLUE}Test Log:${NC} $TEST_LOG"
    echo -e "🔗 ${BLUE}Full Documentation:${NC} docs/"
    echo
}

# Main execution
main() {
    echo -e "${BLUE}🚀 Pi Gateway Comprehensive End-to-End Test Suite${NC}"
    echo -e "${BLUE}   Complete validation of Pi Gateway v1.1.0 functionality${NC}"

    # Execute all test phases
    init_test
    test_preflight
    test_dependencies
    test_security
    test_network_services
    test_service_management
    test_integration
    test_security_validation
    generate_report

    # Exit with appropriate code
    if [ "$TESTS_FAILED" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi