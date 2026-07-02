# kei — build commands
# Usage: just <recipe>

set positional-arguments := true

default: build

# ── Setup & Sync ───────────────────────────────────────────

# Initial setup: configure remotes, fetch upstreams
setup:
    ./scripts/setup.sh

# Sync with upstream asterinas + arm64-support (git merge, not patches)
sync:
    ./scripts/sync-upstream.sh

# ── Build ──────────────────────────────────────────────────

# Build kei kernel for default board (nanopi-r3s, aarch64)
build:
    ./scripts/build.sh nanopi-r3s

# Build for specific board
build-board BOARD:
    ./scripts/build.sh {{BOARD}}

# Build for a specific architecture (raw, no board)
build-arch ARCH:
    cargo osdk build --target {{ARCH}}-unknown-none --release

# Check all BSP crates (host, no kernel deps)
check-bsp:
    cd bsp && cargo check

# ── Test ───────────────────────────────────────────────────

# Boot-test ALL architectures in QEMU (x86_64, aarch64, riscv64, loongarch64)
test-all:
    ./scripts/test-all-arch.sh

# Test one specific architecture
test-arch ARCH:
    ./scripts/test-all-arch.sh {{ARCH}}

# Test on a specific board's QEMU config
test BOARD="nanopi-r3s":
    ./scripts/test.sh {{BOARD}}

# Run ktest unit tests for BSP
test-bsp:
    cd bsp && cargo test

# ── Utilities ──────────────────────────────────────────────

# List supported boards
list-boards:
    ls configs/*.toml | grep -v default | xargs -I{} basename {} .toml

# List supported architectures
list-arch:
    @echo "x86_64      (upstream Tier 1)"
    @echo "aarch64     (via wanywhn arm64-support, PR #3270)"
    @echo "riscv64     (upstream Tier 2)"
    @echo "loongarch64 (upstream Tier 3)"

# Clean build artifacts
clean:
    rm -rf build/ output/
    cargo clean

# Enter build environment shell
dev-shell:
    ./scripts/dev-shell.sh
