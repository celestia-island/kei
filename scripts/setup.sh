#!/usr/bin/env bash
# kei — initial setup
#
# Configures git remotes for the vendoring workflow.
# This is a lightweight script — it only sets up remotes.
# The actual source population happens via `just vendor` and `just pull-arm64`.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== kei setup ==="

echo "[1/2] Configuring git remotes..."

if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "https://github.com/asterinas/asterinas.git"
    echo "  Added: upstream → asterinas/asterinas"
else
    echo "  Exists: upstream"
fi

if ! git remote get-url arm64 >/dev/null 2>&1; then
    git remote add arm64 "https://github.com/wanywhn/asterinas.git"
    echo "  Added: arm64 → wanywhn/asterinas"
else
    echo "  Exists: arm64"
fi

echo ""
echo "[2/2] Status check..."

if [ -d "ostd" ]; then
    echo "  ostd/ present — upstream vendored"
else
    echo "  ostd/ missing — run 'just vendor' to absorb upstream"
fi

if [ -d "ostd/src/arch/aarch64" ]; then
    echo "  ostd/src/arch/aarch64/ present — ARM64 code pulled"
else
    echo "  ostd/src/arch/aarch64/ missing — run 'just pull-arm64'"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "  Populate source:"
echo "    just vendor       # absorb upstream asterinas"
echo "    just pull-arm64   # pull ARM64 architecture code"
echo "    just versions     # show what we're based on"
echo ""
echo "  Build & test:"
echo "    just build        # build kernel"
echo "    just test-all     # QEMU boot test all architectures"
