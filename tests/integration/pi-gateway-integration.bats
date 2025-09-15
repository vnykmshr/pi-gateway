#!/usr/bin/env bats
#
# Pi Gateway - Integration Tests
# Full script execution tests in QEMU Pi environment
#

load '../test_helper/integration_helper'

setup() {
    # Set up integration test environment
    export BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME"
    export PI_GATEWAY_ROOT="$BATS_TEST_DIRNAME/../.."

    # Check if QEMU environment is available
    if [[ ! -f "$PI_GATEWAY_ROOT/tests/qemu/pi-gateway-test/run-pi-vm.sh" ]]; then
        skip "QEMU environment not set up. Run tests/qemu/setup-pi-vm.sh first"
    fi

    # Set integration test timeout
    export INTEGRATION_TIMEOUT=300  # 5 minutes
}

teardown() {
    # Clean up any test artifacts
    cleanup_integration_environment
}

@test "QEMU Pi VM can be started and SSH accessed" {
    run start_pi_vm_with_timeout
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SSH access established" ]]
}

@test "Pi Gateway check-requirements.sh passes in real Pi environment" {
    run execute_script_in_pi_vm "check-requirements.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "System meets minimum requirements" ]]
}

@test "Pi Gateway install-dependencies.sh completes successfully" {
    run execute_script_in_pi_vm "install-dependencies.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "All dependencies installed successfully" ]]
}

@test "Pi Gateway system-hardening.sh applies security configurations" {
    # First install dependencies
    execute_script_in_pi_vm "install-dependencies.sh"

    # Then run hardening
    run execute_script_in_pi_vm "system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "System hardening completed successfully" ]]
}

@test "SSH service is enabled and running after installation" {
    execute_script_in_pi_vm "install-dependencies.sh"

    run check_service_in_pi_vm "ssh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "active (running)" ]]
}

@test "UFW firewall is configured but not enabled by default" {
    execute_script_in_pi_vm "install-dependencies.sh"
    execute_script_in_pi_vm "system-hardening.sh"

    run check_firewall_status_in_pi_vm
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Status: inactive" ]]
}

@test "Fail2ban service is installed and enabled" {
    execute_script_in_pi_vm "install-dependencies.sh"

    run check_service_in_pi_vm "fail2ban"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "enabled" ]]
}

@test "WireGuard tools are available after installation" {
    execute_script_in_pi_vm "install-dependencies.sh"

    run check_command_in_pi_vm "wg --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "wireguard-tools" ]]
}

@test "Pi Gateway service user is created with correct permissions" {
    execute_script_in_pi_vm "install-dependencies.sh"

    run check_user_in_pi_vm "pi-gateway"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "pi-gateway" ]]

    # Check service directories exist
    run check_directory_in_pi_vm "/var/lib/pi-gateway"
    [ "$status" -eq 0 ]
}

@test "System can survive reboot after full installation" {
    execute_script_in_pi_vm "install-dependencies.sh"
    execute_script_in_pi_vm "system-hardening.sh"

    # Reboot the VM
    run reboot_pi_vm
    [ "$status" -eq 0 ]

    # Verify critical services are still running
    run check_service_in_pi_vm "ssh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "active (running)" ]]
}

@test "Pi Gateway installation is idempotent" {
    # Run installation twice
    execute_script_in_pi_vm "install-dependencies.sh"
    run execute_script_in_pi_vm "install-dependencies.sh"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "already" ]]
}

@test "Configuration backups are created properly" {
    execute_script_in_pi_vm "install-dependencies.sh"

    run check_directory_in_pi_vm "/var/backups/pi-gateway"
    [ "$status" -eq 0 ]

    run check_file_in_pi_vm "/var/backups/pi-gateway/sshd_config.*"
    [ "$status" -eq 0 ]
}

@test "Log files are created and contain expected content" {
    execute_script_in_pi_vm "install-dependencies.sh"

    run check_file_in_pi_vm "/tmp/pi-gateway-install-deps.log"
    [ "$status" -eq 0 ]

    run grep_log_in_pi_vm "/tmp/pi-gateway-install-deps.log" "SUCCESS"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SUCCESS" ]]
}

@test "System performance is acceptable after installation" {
    execute_script_in_pi_vm "install-dependencies.sh"
    execute_script_in_pi_vm "system-hardening.sh"

    # Check system load
    run check_system_load_in_pi_vm
    [ "$status" -eq 0 ]

    # Check memory usage
    run check_memory_usage_in_pi_vm
    [ "$status" -eq 0 ]
}

# Security-focused tests
@test "System hardening disables unnecessary services" {
    execute_script_in_pi_vm "install-dependencies.sh"
    execute_script_in_pi_vm "system-hardening.sh"

    # Check that unnecessary services are disabled
    run check_disabled_services_in_pi_vm
    [ "$status" -eq 0 ]
}

@test "Kernel security parameters are applied correctly" {
    execute_script_in_pi_vm "system-hardening.sh"

    run check_sysctl_in_pi_vm "net.ipv4.ip_forward"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "= 0" ]]
}

@test "File permissions are secured appropriately" {
    execute_script_in_pi_vm "system-hardening.sh"

    run check_file_permissions_in_pi_vm "/etc/shadow"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "640" ]]
}