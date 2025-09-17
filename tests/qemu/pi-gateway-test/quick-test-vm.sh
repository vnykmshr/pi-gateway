#!/bin/bash
# Quick Pi test 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Quick Pi VM test..."
echo "Press Ctrl+A then X to quit"
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
  -nographic
