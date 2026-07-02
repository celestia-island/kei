#!/usr/bin/env bash
# kei — generate ARM64 patches from vendor/ state
# Compares upstream Asterinas with the arm64-support fork
# to produce clean patch files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASTERINAS_DIR="$PROJECT_ROOT/vendor/asterinas"
ARM64_DIR="$PROJECT_ROOT/vendor/asterinas-arm64"
PATCHES_DIR="$PROJECT_ROOT/patches/arm64"

echo "=== Generating ARM64 patches ==="

if [ ! -d "$ASTERINAS_DIR" ]; then
    echo "ERROR: vendor/asterinas not found. Run 'just setup' first."
    exit 1
fi

if [ ! -d "$ARM64_DIR" ]; then
    echo "ERROR: vendor/asterinas-arm64 not found. Run 'just setup' first."
    exit 1
fi

mkdir -p "$PATCHES_DIR"

# Generate patch series from diff between upstream and arm64-support
# Focus on architecture-specific files

echo "  Generating patches from diff..."

# Option A: git format-patch (if arm64 branch is based on upstream)
# Option B: plain diff (fallback)
# For now, use git diff to produce a single combined patch

(cd "$ASTERINAS_DIR" && git fetch "$ARM64_DIR" arm64-support:refs/ke/arm64 2>/dev/null || true)

git -C "$ASTERINAS_DIR" format-patch \
    --output-directory "$PATCHES_DIR" \
    --subject-prefix "KEI" \
    main..refs/ke/arm64 \
    2>/dev/null || {
    echo "  format-patch failed — using raw diff instead."
    git -C "$ASTERINAS_DIR" diff main..refs/ke/arm64 \
        -- ostd/ kernel/ Cargo.toml rust-toolchain.toml \
        > "$PATCHES_DIR/0001-kei-arm64.patch"
}

# Update series file
ls "$PATCHES_DIR"/*.patch 2>/dev/null | sort | while read -r p; do
    basename "$p"
done > "$PATCHES_DIR/series"

count=$(wc -l < "$PATCHES_DIR/series")
echo "  Generated $count patch file(s)"
echo "  Patches: $PATCHES_DIR/"
echo "  Series:  $PATCHES_DIR/series"
