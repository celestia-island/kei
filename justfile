# kei — build commands
# Usage: just <recipe>

set positional-arguments := true

default: build

# ── Setup ──────────────────────────────────────────────────

# Full setup: fetch upstream, extract patches, apply, prepare workspace
setup:
    ./scripts/setup.sh

# Update from upstream (rebase patches)
update:
    ./scripts/update.sh

# ── Build ──────────────────────────────────────────────────

# Build kei kernel for default board (nanopi-r3s)
build:
    ./scripts/build.sh nanopi-r3s

# Build for specific board
build-board BOARD:
    ./scripts/build.sh {{BOARD}}

# Build all BSP crates (host check only)
check-bsp:
    cd bsp && cargo check

# ── Test ───────────────────────────────────────────────────

# Boot kernel in QEMU arm64 virt machine
test:
    ./scripts/test.sh nanopi-r3s

# Run ktest unit tests for BSP crates
test-bsp:
    cd bsp && cargo test

# ── Utilities ──────────────────────────────────────────────

# List supported boards
list-boards:
    ls configs/*.toml | grep -v default | xargs -I{} basename {} .toml

# Clean build artifacts
clean:
    rm -rf vendor/ build/ output/
    cargo clean

# Generate patches from current vendor/ state
gen-patches:
    ./scripts/gen-patches.sh

# Enter build environment shell
dev-shell:
    ./scripts/dev-shell.sh
