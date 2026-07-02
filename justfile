# kei — build commands
# Usage: just <recipe>

set positional-arguments := true

default: build

# ── Vendoring (Apple LLVM model: pin + periodically absorb) ──

# Setup: configure remotes
setup:
    ./scripts/setup.sh

# Vendor latest upstream asterinas (squash/replace model, not merge tracking)
vendor:
    ./scripts/vendor-upstream.sh

# Vendor a specific upstream commit/tag
vendor-ref REF:
    ./scripts/vendor-upstream.sh {{REF}}

# Pull ARM64 architecture code from wanywhn fork (one-time or rare re-sync)
pull-arm64:
    ./scripts/pull-arm64.sh

# Pull ARM64 from a specific commit
pull-arm64-ref REF:
    ./scripts/pull-arm64.sh {{REF}}

# Show what upstream versions kei is vendored from
versions:
    @echo "=== Upstream asterinas ==="
    @cat .vendored-upstream 2>/dev/null || echo "  (not vendored yet)"
    @echo ""
    @echo "=== ARM64 source ==="
    @cat .vendored-arm64 2>/dev/null || echo "  (not pulled yet)"

# ── Build ──────────────────────────────────────────────────

# Build kei kernel for default board (nanopi-r3s, aarch64)
build:
    ./scripts/build.sh nanopi-r3s

# Build for specific board
build-board BOARD:
    ./scripts/build.sh {{BOARD}}

# Build for a specific architecture (raw, no board config)
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

# Clean build artifacts
clean:
    rm -rf build/ output/
    cargo clean

# Enter build environment shell
dev-shell:
    ./scripts/dev-shell.sh
