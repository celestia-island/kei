#!/usr/bin/env bash
# kei — sync with upstream asterinas + merge arm64 support
#
# This is the core of kei's upstream tracking strategy.
# Instead of maintaining fragile patch series, kei uses git merge:
#
#   asterinas/asterinas:main  ──merge──▶  kei:dev
#   wanywhn/asterinas:arm64-support  ──merge──▶  kei:dev
#
# Run this script periodically to pull latest upstream changes.
# It handles conflicts by preferring our BSP additions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

UPSTREAM_URL="https://github.com/asterinas/asterinas.git"
ARM64_URL="https://github.com/wanywhn/asterinas.git"

cd "$PROJECT_ROOT"

echo "=== kei upstream sync ==="

# ── Ensure remotes exist ──────────────────────────────────────

echo "[1/4] Configuring git remotes..."
if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$UPSTREAM_URL"
    echo "  Added remote: upstream → $UPSTREAM_URL"
fi
if ! git remote get-url arm64 >/dev/null 2>&1; then
    git remote add arm64 "$ARM64_URL"
    echo "  Added remote: arm64 → $ARM64_URL"
fi

# ── Fetch all upstreams ───────────────────────────────────────

echo "[2/4] Fetching upstream branches..."
git fetch upstream main
echo "  upstream/main fetched"

git fetch arm64 arm64-support
echo "  arm64/arm64-support fetched"

# ── Merge upstream main ───────────────────────────────────────

echo "[3/4] Merging upstream/main..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if git merge-tree $(git merge-base HEAD upstream/main) HEAD upstream/main | grep -q '^<<<<<<<'; then
    echo "  WARNING: conflicts detected merging upstream/main"
    echo "  Attempting merge with 'ours' strategy for kei-specific files..."
    git merge upstream/main --no-edit \
        -X ours \
        -m "sync: merge asterinas upstream main" || {
        echo "  Merge failed. Resolve conflicts manually:"
        echo "    git mergetool"
        echo "    git commit"
        exit 1
    }
else
    git merge upstream/main --no-edit \
        -m "sync: merge asterinas upstream main" || true
fi
echo "  upstream/main merged"

# ── Merge arm64 support ───────────────────────────────────────

echo "[4/4] Merging arm64/arm64-support..."
if git merge-tree $(git merge-base HEAD arm64/arm64-support) HEAD arm64/arm64-support | grep -q '^<<<<<<<'; then
    echo "  WARNING: conflicts detected merging arm64-support"
    echo "  Attempting merge..."
    git merge arm64/arm64-support --no-edit \
        -X theirs \
        -m "sync: merge wanywhn arm64-support (PR #3270)" || {
        echo "  Merge failed. Resolve conflicts manually:"
        echo "    git mergetool"
        echo "    git commit"
        exit 1
    }
else
    git merge arm64/arm64-support --no-edit \
        -m "sync: merge wanywhn arm64-support (PR #3270)" || true
fi
echo "  arm64/arm64-support merged"

# ── Summary ───────────────────────────────────────────────────

echo ""
echo "=== Sync complete ==="
echo "  Branch: $CURRENT_BRANCH"
echo "  Upstream commit: $(git rev-parse --short upstream/main)"
echo "  Arm64 commit:    $(git rev-parse --short arm64/arm64-support)"
echo ""
echo "  Next: just build  (rebuild kernel with new upstream)"
echo "  Next: just test   (verify all architectures still boot)"
