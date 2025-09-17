# Pi Gateway QEMU Testing Environment

This directory contains QEMU-based Raspberry Pi emulation for testing Pi Gateway in a realistic Pi OS environment.

## Setup

1. Install QEMU with ARM64 support:
   ```bash
   brew install qemu  # macOS
   ```

2. Set up the QEMU Pi environment:
   ```bash
   make setup-qemu
   ```

## Usage

### VM Management Scripts

Located in `pi-gateway-test/` after setup:

- `run-pi-vm.sh` - Full Pi VM with networking
- `run-pi-vm-ssh.sh` - Pi VM with SSH access on localhost:5022  
- `quick-test-vm.sh` - Simplified Pi boot test

### Testing Pi Gateway

1. Start the Pi VM:
   ```bash
   cd tests/qemu/pi-gateway-test
   ./run-pi-vm-ssh.sh
   ```

2. Wait for boot (2-3 minutes), then SSH:
   ```bash
   ssh pi@localhost -p 5022
   # Default password: raspberry
   ```

3. Run Pi Gateway setup:
   ```bash
   sudo ./setup.sh --non-interactive
   ```

## Performance Notes

- **Boot time**: 2-5 minutes (realistic Pi timing)
- **Resource usage**: ~1GB RAM, ~4GB disk
- **SSH access**: Available on localhost:5022 after boot

## Comparison with Docker Testing

| Method | Speed | Realism | Use Case |
|--------|-------|---------|----------|
| Docker | Fast (30s) | Good | Development |
| QEMU | Slower (3-5min) | Excellent | Pre-production |
| Real Pi | Native | Perfect | Production |

For daily development, use Docker testing. For final validation, use QEMU.
