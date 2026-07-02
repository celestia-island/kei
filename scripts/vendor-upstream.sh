#!/usr/bin/env bash
# kei — vendor upstream asterinas via squash merge
#
# This implements the "Apple LLVM" model: kei is an independent fork that
# periodically absorbs upstream changes as a single squashed commit.
# Between vendoring rounds, kei is completely independent.
#
# What gets vendored (replaced from upstream):
#   ostd/           (EXCEPT ostd/src/arch/aarch64/ — our code)
#   kernel/         (EXCEPT kernel/src/arch/aarch64/ — our code)
#   osdk/           (build tool, unchanged)
#   test/ tools/    (test infrastructure)
#
# What is preserved (100% kei, never from upstream):
#   ostd/src/arch/aarch64/    (our ARM64 backend)
#   kernel/src/arch/aarch64/  (our ARM64 kernel code)
#   bsp/                      (Board Support Packages)
#   board/ configs/           (board definitions)
#   scripts/ docs/            (our tooling and docs)
#
# Usage:
#   ./scripts/vendor-upstream.sh                # vendor latest upstream main
#   ./scripts/vendor-upstream.sh <commit-ish>   # vendor specific commit/tag
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPSTREAM_URL="https://github.com/asterinas/asterinas.git"
ARM64_URL="https://github.com/wanywhn/asterinas.git"

cd "$PROJECT_ROOT"

UPSTREAM_REF="${1:-main}"

echo "=== kei vendor: upstream asterinas @ $UPSTREAM_REF ==="

# ── Ensure remotes ────────────────────────────────────────────

if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$UPSTREAM_URL"
fi

echo "[1/5] Fetching upstream..."
git fetch upstream "$UPSTREAM_REF"
UPSTREAM_SHA=$(git rev-parse --short "upstream/$UPSTREAM_REF")
echo "  upstream/$UPSTREAM_REF = $UPSTREAM_SHA"

# ── Snapshot our code before vendoring ────────────────────────

echo "[2/5] Snapshotting kei-specific code..."

# List of paths that are OURS (preserve across vendoring)
OUR_PATHS=(
    "ostd/src/arch/aarch64"
    "kernel/src/arch/aarch64"
    "bsp"
    "board"
    "configs"
    "scripts"
    "docs"
    ".github"
    ".gitignore"
    ".editorconfig"
    "justfile"
    "PLAN.md"
    "README.md"
    "rust-toolchain.toml"
    "clippy.toml"
)

# Create a temporary stash of our files
STASH_DIR="$(mktemp -d)"
trap 'rm -rf "$STASH_DIR"' EXIT

for path in "${OUR_PATHS[@]}"; do
    if [ -e "$path" ]; then
        mkdir -p "$STASH_DIR/$(dirname "$path")"
        cp -r "$path" "$STASH_DIR/$path"
    fi
done

# ── Replace upstream code ─────────────────────────────────────

echo "[3/5] Replacing upstream source tree..."

# Directories to refresh from upstream
UPSTREAM_DIRS=("ostd" "kernel" "osdk" "test" "tools")

for dir in "${UPSTREAM_DIRS[@]}"; do
    rm -rf "$dir"
    git checkout "upstream/$UPSTREAM_REF" -- "$dir" 2>/dev/null || {
        echo "  WARNING: $dir not found in upstream (may be renamed/removed)"
    }
done

# Also vendor root-level config files from upstream that we track
for file in Cargo.toml Cargo.lock Makefile OSDK.toml Components.toml VERSION; do
    if git cat-file -e "upstream/$UPSTREAM_REF:$file" 2>/dev/null; then
        git checkout "upstream/$UPSTREAM_REF" -- "$file"
    fi
done

# ── Restore our code ──────────────────────────────────────────

echo "[4/5] Restoring kei-specific code..."

for path in "${OUR_PATHS[@]}"; do
    if [ -e "$STASH_DIR/$path" ]; then
        rm -rf "$path"
        mkdir -p "$(dirname "$path")"
        cp -r "$STASH_DIR/$path" "$path"
    fi
done

# ── Verify aarch64 arch code still exists ─────────────────────

if [ ! -d "ostd/src/arch/aarch64" ]; then
    echo "  WARNING: ostd/src/arch/aarch64/ missing!"
    echo "  Run: ./scripts/pull-arm64.sh to fetch from wanywhn fork"
fi

# ── Record vendored version ───────────────────────────────────

echo "[5/5] Recording vendored version..."

VERSION_FILE=".vendored-upstream"
cat > "$VERSION_FILE" <<EOF
# Tracks which upstream asterinas commit kei is vendored from.
# Updated by scripts/vendor-upstream.sh
upstream_url=$UPSTREAM_URL
upstream_ref=$UPSTREAM_REF
upstream_sha=$(git rev-parse "upstream/$UPSTREAM_REF")
upstream_date=$(git log -1 --format=%ci "upstream/$UPSTREAM_REF" 2>/dev/null || echo "unknown")
vendored_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo ""
echo "=== Vendoring complete ==="
echo "  Upstream: $UPSTREAM_SHA ($UPSTREAM_REF)"
echo "  Date:     $(git log -1 --format=%ci "upstream/$UPSTREAM_REF" 2>/dev/null || echo '?')"
echo ""
echo "  NEXT STEPS:"
echo "    1. Review changes:  git diff --stat"
echo "    2. Fix API breaks:  cargo check (host) && cargo osdk build --target aarch64-unknown-none"
echo "    3. Test all archs:  just test-all"
echo "    4. Commit:          git add -A && git commit -m 'vendor: absorb asterinas $UPSTREAM_SHA'"
echo ""
echo "  If aarch64 code broke due to upstream API changes:"
echo "    Check ostd/src/arch/aarch64/ and kernel/src/arch/aarch64/"
echo "    for compilation errors against the new upstream APIs."
