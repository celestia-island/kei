#!/usr/bin/env bash
# kei — boot kernel in QEMU arm64 virt machine for testing
# Usage: ./scripts/test.sh <board>
set -euo pipefail

BOARD="${1:-nanopi-r3s}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output/$BOARD"
KERNEL="$OUTPUT_DIR/kei-kernel.bin"
DTB="$OUTPUT_DIR/board.dtb"

echo "=== kei smoke test: $BOARD ==="

if [ ! -f "$KERNEL" ]; then
    echo "ERROR: kernel not found at $KERNEL"
    echo "  Run: just build"
    exit 1
fi

echo "Booting in QEMU (arm64 virt)..."
echo "Press Ctrl-A X to exit."
echo ""

# QEMU arm64 virt machine — generic arm64 target
qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a55 \
    -m 2048 \
    -smp 4 \
    -kernel "$KERNEL" \
    ${DTB:+-dtb "$DTB"} \
    -nographic \
    -no-reboot \
    -d cpu_reset,unimp \
    2>&1 | tee "$OUTPUT_DIR/qemu-boot.log"

echo ""
echo "Boot log: $OUTPUT_DIR/qemu-boot.log"
