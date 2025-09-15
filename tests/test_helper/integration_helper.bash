#!/bin/bash
#
# Pi Gateway - Integration Test Helper Functions
# Helper functions for QEMU-based integration testing
#

# Test configuration
readonly QEMU_DIR="$BATS_TEST_DIRNAME/../qemu"
readonly VM_DIR="$QEMU_DIR/pi-gateway-test"
readonly SSH_PORT="5022"
readonly SSH_USER="pi"
readonly SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30"

# VM management functions
start_pi_vm_with_timeout() {
    local timeout=${1:-60}
    local vm_pid

    echo "Starting Pi VM..."

    # Start VM in background
    "$VM_DIR/run-pi-vm.sh" &
    vm_pid=$!

    # Wait for SSH to become available
    local count=0
    while [[ $count -lt $timeout ]]; do
        if ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "echo 'SSH connection established'" 2>/dev/null; then
            echo "SSH access established"
            return 0
        fi
        sleep 2
        ((count += 2))
    done

    # Kill VM if SSH never became available
    kill $vm_pid 2>/dev/null || true
    echo "Failed to establish SSH connection within $timeout seconds"
    return 1
}

execute_script_in_pi_vm() {
    local script_name="$1"
    local script_path="/tmp/pi-gateway/scripts/$script_name"

    # Copy Pi Gateway to VM
    scp $SSH_OPTS -P $SSH_PORT -r "$PI_GATEWAY_ROOT" $SSH_USER@localhost:/tmp/

    # Execute script with sudo
    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "cd /tmp/pi-gateway && sudo ./$script_path"
}

check_service_in_pi_vm() {
    local service_name="$1"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "systemctl status $service_name"
}

check_firewall_status_in_pi_vm() {
    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "sudo ufw status"
}

check_command_in_pi_vm() {
    local command="$1"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "$command"
}

check_user_in_pi_vm() {
    local username="$1"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "id $username"
}

check_directory_in_pi_vm() {
    local directory="$1"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "test -d $directory && echo 'Directory exists: $directory'"
}

check_file_in_pi_vm() {
    local file_pattern="$1"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "ls -la $file_pattern"
}

grep_log_in_pi_vm() {
    local log_file="$1"
    local pattern="$2"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "grep '$pattern' $log_file"
}

reboot_pi_vm() {
    local timeout=${1:-120}

    echo "Rebooting Pi VM..."
    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "sudo reboot" || true

    # Wait for VM to come back up
    sleep 10
    local count=0
    while [[ $count -lt $timeout ]]; do
        if ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "echo 'VM back online'" 2>/dev/null; then
            echo "VM rebooted successfully"
            return 0
        fi
        sleep 5
        ((count += 5))
    done

    echo "VM failed to come back online within $timeout seconds"
    return 1
}

check_system_load_in_pi_vm() {
    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "uptime"
}

check_memory_usage_in_pi_vm() {
    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "free -h"
}

check_disabled_services_in_pi_vm() {
    # Check for services that should be disabled after hardening
    local services=("bluetooth" "avahi-daemon" "triggerhappy")

    for service in "${services[@]}"; do
        if ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "systemctl is-enabled $service 2>/dev/null"; then
            echo "WARNING: $service should be disabled but is enabled"
            return 1
        fi
    done

    echo "All unnecessary services are properly disabled"
    return 0
}

check_sysctl_in_pi_vm() {
    local parameter="$1"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "sysctl $parameter"
}

check_file_permissions_in_pi_vm() {
    local file_path="$1"

    ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "stat -c '%a' $file_path"
}

# VM lifecycle management
setup_clean_vm() {
    echo "Setting up clean VM environment..."

    if [[ ! -f "$VM_DIR/run-pi-vm.sh" ]]; then
        echo "QEMU environment not found. Please run setup-pi-vm.sh first."
        return 1
    fi

    # Restore from clean snapshot
    "$VM_DIR/restore-pi-vm.sh"
}

cleanup_integration_environment() {
    echo "Cleaning up integration test environment..."

    # Kill any running QEMU processes for this test
    pkill -f "qemu-system-aarch64.*pi-gateway-test" 2>/dev/null || true

    # Clean up any temporary files
    rm -rf /tmp/pi-gateway-integration-test.* 2>/dev/null || true
}

# Test utility functions
wait_for_condition() {
    local condition_command="$1"
    local timeout="${2:-60}"
    local interval="${3:-5}"

    local count=0
    while [[ $count -lt $timeout ]]; do
        if eval "$condition_command"; then
            return 0
        fi
        sleep $interval
        ((count += interval))
    done

    echo "Condition not met within $timeout seconds: $condition_command"
    return 1
}

generate_integration_report() {
    local report_file="$1"

    cat > "$report_file" << EOF
Pi Gateway Integration Test Report
Generated: $(date)

VM Information:
$(ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "uname -a" 2>/dev/null || echo "VM not accessible")

System Resources:
$(ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "free -h && df -h" 2>/dev/null || echo "VM not accessible")

Installed Services:
$(ssh $SSH_OPTS -p $SSH_PORT $SSH_USER@localhost "systemctl list-units --type=service --state=running" 2>/dev/null || echo "VM not accessible")
EOF

    echo "Integration test report generated: $report_file"
}

# Export functions for use in BATS tests
export -f start_pi_vm_with_timeout
export -f execute_script_in_pi_vm
export -f check_service_in_pi_vm
export -f check_firewall_status_in_pi_vm
export -f check_command_in_pi_vm
export -f check_user_in_pi_vm
export -f check_directory_in_pi_vm
export -f check_file_in_pi_vm
export -f grep_log_in_pi_vm
export -f reboot_pi_vm
export -f check_system_load_in_pi_vm
export -f check_memory_usage_in_pi_vm
export -f check_disabled_services_in_pi_vm
export -f check_sysctl_in_pi_vm
export -f check_file_permissions_in_pi_vm
export -f setup_clean_vm
export -f cleanup_integration_environment
export -f wait_for_condition
export -f generate_integration_report