#!/bin/bash
#
# Pi Gateway - QEMU Pi Environment Setup
# Sets up Raspberry Pi 4 emulation environment for integration testing
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly QEMU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VM_NAME="pi-gateway-test"
readonly VM_DIR="$QEMU_DIR/$VM_NAME"
readonly IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/2024-07-04-raspios-bookworm-arm64-lite.img.xz"
readonly IMAGE_FILE="$VM_DIR/raspios-bookworm-arm64-lite.img"
readonly KERNEL_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/kernel-qemu-5.4.51-buster"
readonly DTB_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/versatile-pb-buster-5.4.51.dtb"

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

success() {
    echo -e "  ${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

error() {
    echo -e "  ${RED}✗${NC} $1"
    log "ERROR: $1"
}

warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}     Pi Gateway - QEMU Environment Setup      ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

check_prerequisites() {
    info "Checking QEMU installation..."

    if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
        error "qemu-system-aarch64 not found"
        echo
        echo "Please install QEMU with ARM64 support:"
        echo "  macOS: brew install qemu"
        echo "  Ubuntu: sudo apt install qemu-system-arm"
        echo "  Arch: sudo pacman -S qemu-system-aarch64"
        exit 1
    fi
    success "QEMU found: $(qemu-system-aarch64 --version | head -n1)"

    # Check required tools
    local required_tools=("wget" "xz" "dd")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "Required tool not found: $tool"
            exit 1
        fi
    done
    success "All required tools available"
}

create_vm_directory() {
    info "Creating VM directory structure..."

    mkdir -p "$VM_DIR"/{images,snapshots,logs,scripts}
    success "VM directory created: $VM_DIR"
}

download_raspios_image() {
    info "Downloading Raspberry Pi OS ARM64 image..."

    local compressed_image="$VM_DIR/$(basename "$IMAGE_URL")"

    if [[ -f "$IMAGE_FILE" ]]; then
        success "Raspberry Pi OS image already exists"
        return 0
    fi

    if [[ ! -f "$compressed_image" ]]; then
        info "Downloading from $IMAGE_URL..."
        wget -O "$compressed_image" "$IMAGE_URL" || {
            error "Failed to download Raspberry Pi OS image"
            exit 1
        }
        success "Image downloaded successfully"
    fi

    info "Extracting image..."
    xz -d "$compressed_image" -c > "$IMAGE_FILE" || {
        error "Failed to extract image"
        exit 1
    }
    success "Image extracted: $IMAGE_FILE"
}

download_kernel_files() {
    info "Downloading QEMU kernel files..."

    local kernel_file="$VM_DIR/kernel-qemu"
    local dtb_file="$VM_DIR/versatile-pb.dtb"

    if [[ ! -f "$kernel_file" ]]; then
        wget -O "$kernel_file" "$KERNEL_URL" || {
            error "Failed to download kernel"
            exit 1
        }
        success "Kernel downloaded"
    fi

    if [[ ! -f "$dtb_file" ]]; then
        wget -O "$dtb_file" "$DTB_URL" || {
            error "Failed to download DTB"
            exit 1
        }
        success "DTB downloaded"
    fi
}

configure_ssh_access() {
    info "Configuring SSH access..."

    # Mount the image to enable SSH
    local loop_device
    loop_device=$(sudo losetup -P --show --find "$IMAGE_FILE")

    if [[ -z "$loop_device" ]]; then
        error "Failed to create loop device"
        exit 1
    fi

    local mount_point="$VM_DIR/mnt"
    mkdir -p "$mount_point"

    # Mount the boot partition (usually partition 1)
    sudo mount "${loop_device}p1" "$mount_point" || {
        sudo losetup -d "$loop_device"
        error "Failed to mount boot partition"
        exit 1
    }

    # Enable SSH by creating the ssh file
    sudo touch "$mount_point/ssh"
    success "SSH enabled on boot partition"

    # Unmount and detach
    sudo umount "$mount_point"
    sudo losetup -d "$loop_device"

    success "SSH access configured"
}

create_vm_scripts() {
    info "Creating VM management scripts..."

    # Create run-pi-vm.sh
    cat > "$VM_DIR/run-pi-vm.sh" << 'EOF'
#!/bin/bash
# Start Pi Gateway test VM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="pi-gateway-test"

qemu-system-aarch64 \
  -M raspi3b \
  -cpu cortex-a72 \
  -smp 4 \
  -m 1G \
  -kernel "$SCRIPT_DIR/kernel-qemu" \
  -dtb "$SCRIPT_DIR/versatile-pb.dtb" \
  -drive format=raw,file="$SCRIPT_DIR/raspios-bookworm-arm64-lite.img" \
  -append "root=/dev/mmcblk0p2 rw rootwait console=ttyAMA0" \
  -netdev user,id=net0,hostfwd=tcp::5022-:22 \
  -device rtl8139,netdev=net0 \
  -nographic \
  -serial stdio \
  -monitor telnet:127.0.0.1:55555,server,nowait
EOF
    chmod +x "$VM_DIR/run-pi-vm.sh"
    success "run-pi-vm.sh created"

    # Create restore-pi-vm.sh
    cat > "$VM_DIR/restore-pi-vm.sh" << 'EOF'
#!/bin/bash
# Restore Pi Gateway test VM from clean snapshot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_FILE="$SCRIPT_DIR/snapshots/clean-install.qcow2"
IMAGE_FILE="$SCRIPT_DIR/raspios-bookworm-arm64-lite.img"

if [[ -f "$SNAPSHOT_FILE" ]]; then
    echo "Restoring VM from clean snapshot..."
    cp "$SNAPSHOT_FILE" "$IMAGE_FILE"
    echo "VM restored successfully"
else
    echo "No clean snapshot found. Run setup-pi-vm.sh first."
    exit 1
fi
EOF
    chmod +x "$VM_DIR/restore-pi-vm.sh"
    success "restore-pi-vm.sh created"

    # Create destroy-pi-vm.sh
    cat > "$VM_DIR/destroy-pi-vm.sh" << 'EOF'
#!/bin/bash
# Destroy Pi Gateway test VM and clean up resources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Destroying Pi Gateway test VM..."

# Kill any running QEMU processes
pkill -f "qemu-system-aarch64.*pi-gateway-test" || true

# Clean up VM files (but keep snapshots)
rm -f "$SCRIPT_DIR/raspios-bookworm-arm64-lite.img"
rm -rf "$SCRIPT_DIR/mnt"

echo "VM destroyed successfully"
EOF
    chmod +x "$VM_DIR/destroy-pi-vm.sh"
    success "destroy-pi-vm.sh created"
}

create_snapshot() {
    info "Creating clean VM snapshot..."

    local snapshot_dir="$VM_DIR/snapshots"
    mkdir -p "$snapshot_dir"

    # Create a clean snapshot for quick restoration
    cp "$IMAGE_FILE" "$snapshot_dir/clean-install.qcow2"
    success "Clean snapshot created"
}

print_usage_info() {
    echo
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}            Setup Complete!                   ${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
    echo "Pi Gateway QEMU environment is ready!"
    echo
    echo "Usage:"
    echo -e "  ${GREEN}Start VM:${NC}    $VM_DIR/run-pi-vm.sh"
    echo -e "  ${GREEN}Restore VM:${NC}  $VM_DIR/restore-pi-vm.sh"
    echo -e "  ${GREEN}Destroy VM:${NC}  $VM_DIR/destroy-pi-vm.sh"
    echo
    echo "SSH Access:"
    echo -e "  ${YELLOW}ssh pi@localhost -p 5022${NC}"
    echo -e "  Default password: ${YELLOW}raspberry${NC}"
    echo
    echo "Monitor Console:"
    echo -e "  ${YELLOW}telnet localhost 55555${NC}"
    echo
}

main() {
    print_header
    log "Starting Pi Gateway QEMU environment setup"

    check_prerequisites
    create_vm_directory
    download_raspios_image
    download_kernel_files
    configure_ssh_access
    create_vm_scripts
    create_snapshot

    print_usage_info

    log "QEMU environment setup completed successfully"
}

# Handle script interruption
trap 'echo -e "\n${YELLOW}Setup interrupted${NC}"; exit 130' INT

# Check if being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi