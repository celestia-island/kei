# kei — build commands
# Usage: just <recipe>

set unstable
set shell := ["bash", "-c"]
set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

python_cmd := if os_family() == "windows" {
    "python"
} else if which("python3") != "" {
    "python3"
} else {
    "python"
}

default: build

# ── Vendoring (Apple LLVM model: pin + periodically absorb) ──

setup:
    {{python_cmd}} scripts/setup.py

vendor:
    {{python_cmd}} scripts/vendor_upstream.py

vendor-ref REF:
    {{python_cmd}} scripts/vendor_upstream.py {{REF}}

pull-arm64:
    {{python_cmd}} scripts/pull_arm64.py

pull-arm64-ref REF:
    {{python_cmd}} scripts/pull_arm64.py {{REF}}

versions:
    @echo "=== Upstream asterinas ==="
    @cat .vendored-upstream 2>/dev/null || echo "  (not vendored yet — run 'just vendor')"
    @echo ""
    @echo "=== ARM64 source ==="
    @cat .vendored-arm64 2>/dev/null || echo "  (not pulled yet — run 'just pull-arm64')"

# ── Build ──────────────────────────────────────────────────

build:
    {{python_cmd}} scripts/build.py nanopi-r3s

build-board BOARD:
    {{python_cmd}} scripts/build.py {{BOARD}}

build-arch ARCH:
    cargo osdk build --target {{ARCH}}-unknown-none --release

check-bsp:
    cd bsp && cargo check

initramfs:
    {{python_cmd}} scripts/initramfs.py --arch aarch64

initramfs-force:
    {{python_cmd}} scripts/initramfs.py --arch aarch64 --force

# ── Test ───────────────────────────────────────────────────

test-all:
    {{python_cmd}} scripts/test_all_arch.py

test-arch ARCH:
    {{python_cmd}} scripts/test_all_arch.py {{ARCH}}

test BOARD="nanopi-r3s":
    {{python_cmd}} scripts/test.py {{BOARD}}

test-bsp:
    cd bsp && cargo test

# ── Utilities ──────────────────────────────────────────────

list-boards:
    ls configs/*.toml | grep -v default | xargs -I{} basename {} .toml

list-arch:
    @echo "x86_64      (upstream Tier 1)"
    @echo "aarch64     (via wanywhn arm64-support, PR #3270)"
    @echo "riscv64     (upstream Tier 2)"
    @echo "loongarch64 (upstream Tier 3)"

clean:
    rm -rf build/ output/
    cargo clean

dev-shell:
    {{python_cmd}} scripts/dev_shell.py
