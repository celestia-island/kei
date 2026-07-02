#!/usr/bin/env bash
# kei — build Asterinas kernel for target board
# Usage: ./scripts/build.sh <board> [--release]
set -euo pipefail

BOARD="${1:-nanopi-r3s}"
PROFILE="${2:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASTERINAS_DIR="$PROJECT_ROOT/vendor/asterinas"
OUTPUT_DIR="$PROJECT_ROOT/output/$BOARD"

echo "=== kei build: $BOARD ($PROFILE) ==="

# Check setup
if [ ! -d "$ASTERINAS_DIR" ]; then
    echo "ERROR: vendor/asterinas not found. Run 'just setup' first."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ── Load board config ────────────────────────────────────────
CONFIG_FILE="$PROJECT_ROOT/configs/$BOARD.toml"
if [ -f "$CONFIG_FILE" ]; then
    echo "[1/4] Loading board config: $CONFIG_FILE"
    # Extract values (simple grep-based; a proper parser TBD)
    ARCH=$(grep 'arch' "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
    BSP=$(grep 'bsp_crate' "$CONFIG_FILE" | head -1 | cut -d'"' -f2)
else
    echo "WARNING: config not found, using defaults"
    ARCH="aarch64"
    BSP="bsp-rk3566"
fi

RUST_TARGET="${ARCH}-unknown-none"
echo "  Target: $RUST_TARGET"
echo "  BSP:    $BSP"

# ── Copy BSP into Asterinas workspace ────────────────────────
echo "[2/4] Linking BSP crates into kernel workspace..."
# TODO: add BSP crate to $ASTERINAS_DIR/Cargo.toml workspace members
#       or use a separate overlay workspace

# ── Build kernel ─────────────────────────────────────────────
echo "[3/4] Building Asterinas kernel..."
(cd "$ASTERINAS_DIR" && \
    cargo osdk build \
        --target "$RUST_TARGET" \
        --profile "$PROFILE" \
        --bsp "$BSP" \
        2>&1) || {
    echo "ERROR: kernel build failed."
    echo "  TIP: check that ARM64 patches are applied (just gen-patches)"
    echo "  TIP: check that RUST_TARGET=$RUST_TARGET is in rust-toolchain.toml"
    exit 1
}

# ── Copy artifacts ───────────────────────────────────────────
echo "[4/4] Copying build artifacts..."
# TODO: locate the actual binary from cargo osdk output
# For now, assume typical output paths
if [ -f "$ASTERINAS_DIR/target/$RUST_TARGET/$PROFILE/kei-kernel" ]; then
    cp "$ASTERINAS_DIR/target/$RUST_TARGET/$PROFILE/kei-kernel" \
       "$OUTPUT_DIR/kei-kernel.bin"
fi

# Copy device tree
DTB_SRC="$PROJECT_ROOT/board/$BOARD/device-tree"
if [ -d "$DTB_SRC" ] && [ -f "$DTB_SRC"/*.dts ]; then
    echo "  Device tree source found in $DTB_SRC"
    # TODO: compile .dts → .dtb (requires dtc)
    # dtc -I dts -O dtb -o "$OUTPUT_DIR/board.dtb" "$DTB_SRC"/*.dts
fi

echo ""
echo "=== Build complete ==="
echo "  Kernel: $OUTPUT_DIR/kei-kernel.bin"
echo "  DTB:    $OUTPUT_DIR/board.dtb"
echo ""
echo "  Next: copy to aris for firmware packaging"
echo "    cp output/$BOARD/kei-kernel.bin ../aris/output/$BOARD/Image"
echo "    cp output/$BOARD/board.dtb     ../aris/output/$BOARD/"
