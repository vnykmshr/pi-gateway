#!/bin/bash
# Start Pi Gateway test VM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting Pi Gateway test VM..."
echo "SSH may be available on localhost:5022 after Pi boots"
echo "Default credentials: pi/raspberry"
echo "Press Ctrl+A then X to quit QEMU"
echo

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
  -device usb-net,netdev=net0 \
  -nographic \
  -serial stdio \
  -monitor telnet:127.0.0.1:55556,server,nowait
