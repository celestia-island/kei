#!/usr/bin/env bash
# kei — update from upstream and rebase patches
# Pulls latest asterinas/asterinas and wanywhn/asterinas,
# regenerates patches, and applies them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== kei update ==="

echo "[1/3] Updating upstream Asterinas..."
(cd "$PROJECT_ROOT/vendor/asterinas" && git pull --ff-only origin main 2>/dev/null) || {
    echo "  Warning: could not fast-forward. Manual rebase required."
}

echo "[2/3] Updating ARM64 fork..."
if [ -d "$PROJECT_ROOT/vendor/asterinas-arm64" ]; then
    (cd "$PROJECT_ROOT/vendor/asterinas-arm64" && git pull --ff-only origin arm64-support 2>/dev/null) || {
        echo "  Warning: could not fast-forward ARM64 fork."
    }
fi

echo "[3/3] Regenerating and applying patches..."
"$SCRIPT_DIR/gen-patches.sh"

echo ""
echo "=== Update complete ==="
echo "  Next: just build"
