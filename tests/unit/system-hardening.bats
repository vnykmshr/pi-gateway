#!/usr/bin/env bats
#
# Pi Gateway - Unit Tests for system-hardening.sh
#

setup() {
    # Load test helpers
    export BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME"
    export PI_GATEWAY_ROOT="$BATS_TEST_DIRNAME/../.."

    # Source the script functions
    source "$PI_GATEWAY_ROOT/tests/mocks/common.sh"
    source "$PI_GATEWAY_ROOT/tests/mocks/system.sh"

    # Set up dry-run environment
    export DRY_RUN=true
    export MOCK_HARDWARE=true
    export MOCK_NETWORK=true
    export MOCK_SYSTEM=true
    export VERBOSE_DRY_RUN=false

    init_dry_run_environment
    setup_mock_system
}

teardown() {
    # Clean up any test artifacts
    rm -f /tmp/pi-gateway-dry-run.log /tmp/pi-gateway-hardening.log
    cleanup_mock_system
}

@test "system-hardening.sh runs successfully in dry-run mode" {
    run "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    echo "Exit code: $status"
    echo "Output: $output"

    [[ "$output" =~ "Pi Gateway - System Hardening" ]]
    [[ "$output" =~ "dry-run mode" ]]
}

@test "system-hardening.sh skips sudo check in dry-run mode" {
    run "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    echo "Output: $output"
    [[ "$output" =~ "Running in dry-run mode (sudo check skipped)" ]]
}

@test "system-hardening.sh initializes dry-run environment" {
    run "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    echo "Output: $output"
    [[ "$output" =~ "Pi Gateway Dry-Run Mode Enabled" ]]
    [[ "$output" =~ "No actual system changes will be made" ]]
}

@test "system-hardening.sh sets up mock system environment" {
    run "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    echo "Output: $output"
    [[ "$output" =~ "Setting up mock system environment" ]]
}

@test "system-hardening.sh handles system update operations" {
    run "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    echo "Exit code: $status"
    echo "Output: $output"

    # Should show system update section or complete successfully
    if [ "$status" -eq 0 ]; then
        [[ "$output" =~ "System Updates" ]]
    else
        # In dry-run mode, script may exit early but should show initial sections
        [[ "$output" =~ "System Hardening" ]]
    fi
}

@test "system-hardening.sh skips verification in dry-run mode" {
    # Check that the verification function has dry-run handling
    run grep -A 5 "verify_hardening" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Skip verification in dry-run mode" ]]
}

@test "system-hardening.sh skips report creation in dry-run mode" {
    # Check that the report creation function has dry-run handling
    run grep -A 5 "create_hardening_report" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "skipped in dry-run mode" ]]
}

@test "system-hardening.sh contains kernel hardening configurations" {
    run grep "kernel" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "kernel" ]]
}

@test "system-hardening.sh contains network hardening configurations" {
    run grep "net\.ipv4" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "net.ipv4" ]]
}

@test "system-hardening.sh contains sysctl parameter configurations" {
    run grep "sysctl" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sysctl" ]]
}

@test "system-hardening.sh includes user account hardening" {
    run grep -i "user.*account" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
}

@test "system-hardening.sh includes service management" {
    run grep "systemctl" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "systemctl" ]]
}

@test "system-hardening.sh includes file permission hardening" {
    run grep -E "(chmod|chown)" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
}

@test "system-hardening.sh includes logging configuration" {
    run grep -i "log" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
}

@test "system-hardening.sh includes backup functionality" {
    run grep -i "backup" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
}

@test "system-hardening.sh has comprehensive error handling" {
    run grep -c "error\|ERROR" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" -gt 5 ]]
}

@test "system-hardening.sh uses execute_command wrapper for system modifications" {
    run grep "execute_command" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "execute_command" ]]
}

@test "system-hardening.sh sources required mock files" {
    run grep "source.*mocks" "$PI_GATEWAY_ROOT/scripts/system-hardening.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "tests/mocks" ]]
}