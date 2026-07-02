#!/usr/bin/env bash
# kei — initial setup
#
# kei is a downstream fork of asterinas/asterinas. This script prepares
# the development environment by ensuring the upstream sources are
# fetched and the arm64 branch is merged.
#
# Unlike the old patch-based approach, kei uses git merge to track
# both upstream asterinas and the wanywhn arm64-support branch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=== kei setup ==="

# ── Verify git remotes ────────────────────────────────────────

echo "[1/3] Verifying git remotes..."

if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "https://github.com/asterinas/asterinas.git"
    echo "  Added remote: upstream"
else
    echo "  upstream remote exists"
fi

if ! git remote get-url arm64 >/dev/null 2>&1; then
    git remote add arm64 "https://github.com/wanywhn/asterinas.git"
    echo "  Added remote: arm64"
else
    echo "  arm64 remote exists"
fi

# ── Fetch branches ────────────────────────────────────────────

echo "[2/3] Fetching upstream branches..."
git fetch upstream main --depth=50 2>/dev/null || {
    echo "  WARNING: could not fetch upstream/main (offline?)"
}
echo "  upstream/main: $(git rev-parse --short upstream/main 2>/dev/null || echo 'not fetched')"

git fetch arm64 arm64-support --depth=50 2>/dev/null || {
    echo "  WARNING: could not fetch arm64/arm64-support (offline?)"
}
echo "  arm64/arm64-support: $(git rev-parse --short arm64/arm64-support 2>/dev/null || echo 'not fetched')"

# ── Verify workspace ──────────────────────────────────────────

echo "[3/3] Verifying workspace..."

if [ -d "ostd" ] && [ -d "kernel" ]; then
    echo "  ostd/ and kernel/ directories present"
else
    echo "  NOTE: This is a kei skeleton repo."
    echo "  To populate with full asterinas source:"
    echo "    git fetch upstream main"
    echo "    git checkout upstream/main -- ostd/ kernel/ osdk/ test/ tools/"
    echo "    git fetch arm64 arm64-support"
    echo "    git merge arm64/arm64-support"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "  Sync with upstream:  just sync"
echo "  Build kernel:        just build"
echo "  Test all archs:      just test-all"
