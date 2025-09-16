#!/usr/bin/env bats
#
# Pi Gateway - Unit Tests for check-requirements.sh
#

setup() {
    # Load test helpers
    export BATS_TEST_DIRNAME="$BATS_TEST_DIRNAME"
    export PI_GATEWAY_ROOT="$BATS_TEST_DIRNAME/../.."

    # Source the script functions
    source "$PI_GATEWAY_ROOT/tests/mocks/common.sh"
    source "$PI_GATEWAY_ROOT/tests/mocks/hardware.sh"
    source "$PI_GATEWAY_ROOT/tests/mocks/network.sh"

    # Set up dry-run environment
    export DRY_RUN=true
    export MOCK_HARDWARE=true
    export MOCK_NETWORK=true
    export VERBOSE_DRY_RUN=false

    init_dry_run_environment
}

teardown() {
    # Clean up any test artifacts
    rm -f /tmp/pi-gateway-dry-run.log
}

@test "check-requirements.sh runs successfully in dry-run mode" {
    run "$PI_GATEWAY_ROOT/scripts/check-requirements.sh"
    echo "Exit code: $status"
    echo "Output: $output"
    [ "$status" -eq 0 ]
}

@test "check-requirements.sh detects mocked Pi hardware" {
    export MOCK_PI_MODEL="Raspberry Pi 4 Model B Rev 1.4"
    export MOCK_PI_MEMORY_MB=4096

    run "$PI_GATEWAY_ROOT/scripts/check-requirements.sh"
    echo "Output: $output"
    [[ "$output" =~ "Raspberry Pi 4 Model B Rev 1.4" ]]
    [[ "$output" =~ "4096MB" ]]
}

@test "check-requirements.sh validates memory requirements" {
    export MOCK_PI_MEMORY_MB=512

    run "$PI_GATEWAY_ROOT/scripts/check-requirements.sh"
    echo "Output: $output"
    [[ "$output" =~ "Insufficient RAM" ]]
}

@test "check-requirements.sh validates storage requirements" {
    export MOCK_PI_STORAGE_GB=4

    run "$PI_GATEWAY_ROOT/scripts/check-requirements.sh"
    echo "Output: $output"
    [[ "$output" =~ "Limited storage space" ]]
}

@test "check-requirements.sh handles network connectivity checks" {
    export MOCK_INTERNET_CONNECTIVITY=true
    export MOCK_DNS_RESOLUTION=true

    run "$PI_GATEWAY_ROOT/scripts/check-requirements.sh"
    echo "Output: $output"
    [[ "$output" =~ "Internet connectivity available" ]]
}

@test "check-requirements.sh handles offline scenarios" {
    export MOCK_INTERNET_CONNECTIVITY=false

    run "$PI_GATEWAY_ROOT/scripts/check-requirements.sh"
    echo "Output: $output"
    [[ "$output" =~ "No internet connectivity" ]]
}

@test "dry-run mode produces expected output markers" {
    run "$PI_GATEWAY_ROOT/scripts/check-requirements.sh"
    echo "Output: $output"
    [[ "$output" =~ "Pi Gateway Dry-Run Mode Enabled" ]]
    [[ "$output" =~ "No actual system changes will be made" ]]
}