#!/usr/bin/env bash
# kei — pull ARM64 architecture code from wanywhn/asterinas
#
# This is a ONE-TIME operation (or rare re-sync). The arm64 code, once
# pulled into kei, is maintained independently. We do NOT track the
# wanywhn fork continuously.
#
# Usage:
#   ./scripts/pull-arm64.sh                     # pull latest arm64-support
#   ./scripts/pull-arm64.sh <commit-ish>        # pull specific commit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARM64_URL="https://github.com/wanywhn/asterinas.git"

cd "$PROJECT_ROOT"

ARM64_REF="${1:-arm64-support}"

echo "=== kei: pull ARM64 architecture code ==="

# ── Ensure remote ─────────────────────────────────────────────

if ! git remote get-url arm64 >/dev/null 2>&1; then
    git remote add arm64 "$ARM64_URL"
fi

echo "[1/3] Fetching wanywhn/asterinas ($ARM64_REF)..."
git fetch arm64 "$ARM64_REF"
ARM64_SHA=$(git rev-parse --short "arm64/$ARM64_REF")
echo "  arm64/$ARM64_REF = $ARM64_SHA"

# ── Extract arm64-specific files ──────────────────────────────

echo "[2/3] Extracting ARM64 architecture code..."

# OSTD architecture backend
mkdir -p ostd/src/arch
git checkout "arm64/$ARM64_REF" -- ostd/src/arch/aarch64/ 2>/dev/null || {
    echo "  Fetching ostd/src/arch/aarch64/ from tree..."
    git archive "arm64/$ARM64_REF" ostd/src/arch/aarch64/ | tar x -C . 2>/dev/null || {
        echo "  WARNING: could not extract ostd/src/arch/aarch64/"
    }
}

# Kernel architecture code
mkdir -p kernel/src/arch
git checkout "arm64/$ARM64_REF" -- kernel/src/arch/aarch64/ 2>/dev/null || {
    echo "  Fetching kernel/src/arch/aarch64/ from tree..."
    git archive "arm64/$ARM64_REF" kernel/src/arch/aarch64/ | tar x -C . 2>/dev/null || {
        echo "  WARNING: could not extract kernel/src/arch/aarch64/"
    }
}

# Check for other arm64-related changes (OSDK config, CI, etc.)
echo "  Checking for OSDK/build changes..."
git diff "upstream/main..arm64/$ARM64_REF" -- OSDK.toml Makefile rust-toolchain.toml 2>/dev/null | head -50 || true

# ── Record arm64 version ──────────────────────────────────────

echo "[3/3] Recording ARM64 source version..."

cat > ".vendored-arm64" <<EOF
# Tracks which wanywhn/asterinas commit the arm64 code was pulled from.
# This is a point-in-time snapshot, NOT continuous tracking.
arm64_url=$ARM64_URL
arm64_ref=$ARM64_REF
arm64_sha=$(git rev-parse "arm64/$ARM64_REF")
arm64_date=$(git log -1 --format=%ci "arm64/$ARM64_REF" 2>/dev/null || echo "unknown")
pulled_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
note=Point-in-time snapshot. Maintained independently in kei thereafter.
EOF

echo ""
echo "=== ARM64 pull complete ==="
echo "  Source: wanywhn/asterinas $ARM64_SHA ($ARM64_REF)"
echo ""
echo "  The arm64 code is now part of kei and maintained independently."
echo "  To re-sync from wanywhn (rare): run this script again."
echo ""
echo "  NEXT: audit the code (LLM-generated, needs review)"
echo "    grep -rn 'TODO\|FIXME\|HACK' ostd/src/arch/aarch64/"
echo "    cargo osdk build --target aarch64-unknown-none"
