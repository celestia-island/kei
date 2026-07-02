#!/usr/bin/env bash
# kei — build kernel for target board
#
# In the fork model, kei IS the kernel source tree. There is no vendor/
# directory. The ostd/, kernel/, and osdk/ directories live at the repo root.
# This script runs `cargo osdk build` directly in the kei tree.
#
# Usage: ./scripts/build.sh <board> [profile]
set -euo pipefail

BOARD="${1:-nanopi-r3s}"
PROFILE="${2:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output/$BOARD"

echo "=== kei build: $BOARD ($PROFILE) ==="

# ── Verify kei is populated ───────────────────────────────────

if [ ! -d "$PROJECT_ROOT/ostd" ] || [ ! -d "$PROJECT_ROOT/kernel" ]; then
    echo "ERROR: kei tree not populated."
    echo "  This skeleton repo doesn't contain the asterinas source yet."
    echo "  Run 'just setup && just sync' to fetch and merge upstream."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ── Load board config ────────────────────────────────────────

CONFIG_FILE="$PROJECT_ROOT/configs/$BOARD.toml"
if [ -f "$CONFIG_FILE" ]; then
    echo "[1/4] Loading board config: $CONFIG_FILE"
    ARCH=$(grep '^arch' "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    BSP=$(grep 'bsp_crate' "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    DTB_NAME=$(grep '^dtb' "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
else
    echo "WARNING: config not found, using defaults"
    ARCH="aarch64"
    BSP="bsp-rk3566"
    DTB_NAME=""
fi

# Map arch to Rust target triple
case "$ARCH" in
    x86_64)      RUST_TARGET="x86_64-unknown-none" ;;
    aarch64)     RUST_TARGET="aarch64-unknown-none" ;;
    riscv64)     RUST_TARGET="riscv64imac-unknown-none-elf" ;;
    loongarch64) RUST_TARGET="loongarch64-unknown-none-softfloat" ;;
    *) echo "ERROR: unknown arch '$ARCH'"; exit 1 ;;
esac

echo "  Target: $RUST_TARGET"
echo "  BSP:    $BSP"

# ── Build kernel ─────────────────────────────────────────────

echo "[2/4] Building kernel via cargo osdk..."
cd "$PROJECT_ROOT"
cargo osdk build \
    --target "$RUST_TARGET" \
    --profile "$PROFILE" \
    2>&1 || {
    echo "ERROR: kernel build failed."
    echo "  TIP: verify ostd/src/arch/aarch64/ exists (just sync)"
    echo "  TIP: verify $RUST_TARGET is in rust-toolchain.toml"
    exit 1
}

# ── Copy artifacts ───────────────────────────────────────────

echo "[3/4] Copying build artifacts..."
KERNEL_BIN="$PROJECT_ROOT/target/$RUST_TARGET/$PROFILE/kei-kernel"
if [ -f "$KERNEL_BIN" ]; then
    cp "$KERNEL_BIN" "$OUTPUT_DIR/kei-kernel.bin"
    echo "  Kernel: $OUTPUT_DIR/kei-kernel.bin"
elif [ -f "${KERNEL_BIN}.bin" ]; then
    cp "${KERNEL_BIN}.bin" "$OUTPUT_DIR/kei-kernel.bin"
    echo "  Kernel: $OUTPUT_DIR/kei-kernel.bin"
else
    echo "  WARNING: kernel binary not found at expected path"
    echo "  Check target/$RUST_TARGET/$PROFILE/ for the output"
fi

# ── Compile device tree ──────────────────────────────────────

echo "[4/4] Compiling device tree..."
if [ -n "$DTB_NAME" ] && command -v dtc >/dev/null 2>&1; then
    DTB_SRC="$PROJECT_ROOT/board/$BOARD/device-tree"
    if ls "$DTB_SRC"/*.dts >/dev/null 2>&1; then
        dtc -I dts -O dtb -o "$OUTPUT_DIR/board.dtb" "$DTB_SRC"/*.dts 2>/dev/null || true
        echo "  DTB: $OUTPUT_DIR/board.dtb"
    fi
else
    echo "  (dtc not available or no DTB configured — skipping)"
fi

echo ""
echo "=== Build complete ==="
echo "  Output: $OUTPUT_DIR/"
echo ""
echo "  Next: feed into aris for firmware packaging"
echo "    cp output/$BOARD/kei-kernel.bin ../aris/output/$BOARD/Image"
