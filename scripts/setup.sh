#!/usr/bin/env bash
# kei — fetch Asterinas upstream, generate & apply ARM64 patches
# Run once after cloning kei.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/vendor"
ASTERINAS_DIR="$VENDOR_DIR/asterinas"

echo "=== kei setup ==="

# ── Fetch upstream Asterinas ─────────────────────────────────
echo "[1/3] Fetching upstream Asterinas..."
if [ -d "$ASTERINAS_DIR" ]; then
    echo "  Already exists: $ASTERINAS_DIR"
    echo "  Run 'just update' to pull latest, or 'rm -rf $ASTERINAS_DIR' to re-fetch."
else
    mkdir -p "$VENDOR_DIR"
    git clone --depth 1 --branch main \
        https://github.com/asterinas/asterinas.git \
        "$ASTERINAS_DIR"
    echo "  Cloned asterinas/asterinas (main)"
fi

# ── Fetch ARM64 fork (wanywhn/asterinas) ────────────────────
echo "[2/3] Fetching ARM64 support branch..."
ARM64_DIR="$VENDOR_DIR/asterinas-arm64"

if [ ! -d "$ARM64_DIR" ]; then
    git clone --depth 1 --branch arm64-support \
        https://github.com/wanywhn/asterinas.git \
        "$ARM64_DIR"
    echo "  Cloned wanywhn/asterinas (arm64-support)"
else
    (cd "$ARM64_DIR" && git pull --ff-only origin arm64-support 2>/dev/null || true)
    echo "  Updated wanywhn/asterinas (arm64-support)"
fi

# ── Generate patches ─────────────────────────────────────────
echo "[3/3] Generating ARM64 patches..."
PATCHES_DIR="$PROJECT_ROOT/patches/arm64"
mkdir -p "$PATCHES_DIR"

# Diff: upstream main vs wanywhn arm64-support
# Focus on: ostd/src/arch/ (new aarch64), kernel/src/arch/ (new aarch64),
#           changes to ostd/src/lib.rs, kernel/src/lib.rs, Cargo.toml, etc.
(cd "$ASTERINAS_DIR" && git fetch "$ARM64_DIR" arm64-support:refs/heads/tmp-arm64 2>/dev/null || true)

# Generate one patch per logical change
# TODO: refine this to produce clean, split patches (e.g. via git format-patch)
echo "  TODO: extract patches from wanywhn/asterinas diff"
echo "  For now, check patches/arm64/series for manual patch list"
echo "  Run 'just gen-patches' to regenerate from vendor/ state"

# ── Apply patches ────────────────────────────────────────────
if [ -f "$PATCHES_DIR/series" ] && [ -s "$PATCHES_DIR/series" ]; then
    echo "  Applying patches..."
    (cd "$ASTERINAS_DIR" && quilt push -a 2>/dev/null) || {
        echo "  Warning: automatic patch apply failed."
        echo "  Apply manually: cd $ASTERINAS_DIR && quilt push -a"
    }
else
    echo "  No patches to apply (patches/arm64/series is empty or missing)"
    echo "  Run 'just gen-patches' once patches are ready"
fi

# ── Link BSP crates into Asterinas workspace ─────────────────
echo ""
echo "=== Setup complete ==="
echo ""
echo "  Upstream:   $ASTERINAS_DIR"
echo "  ARM64 fork: $ARM64_DIR"
echo "  Patches:    $PATCHES_DIR"
echo ""
echo "  Next steps:"
echo "    1. Generate patches: just gen-patches"
echo "    2. Build kernel:     just build"
echo "    3. Test in QEMU:     just test"
