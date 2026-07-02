#!/usr/bin/env bash
# kei — enter build environment shell
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export PATH="$PROJECT_ROOT/vendor/asterinas/osdk/target/release:$PATH"
export KEI_PATCHES="$PROJECT_ROOT/patches/arm64"
export KEI_BSP="$PROJECT_ROOT/bsp"
export KEI_BOARD="$PROJECT_ROOT/board"

echo "=== kei dev shell ==="
echo "KEI_PATCHES=$KEI_PATCHES"
echo "KEI_BSP=$KEI_BSP"
echo "KEI_BOARD=$KEI_BOARD"
echo ""

exec "${SHELL:-bash}" "$@"
