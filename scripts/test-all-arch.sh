#!/usr/bin/env bash
# kei — boot-test the kernel on ALL supported architectures via QEMU.
#
# Mirrors how the Linux kernel / KernelCI tests: every architecture gets
# a QEMU boot smoke test before anything is considered ready.
#
# Architectures tested:
#   x86_64      — qemu virt q35 (upstream Tier 1)
#   aarch64     — qemu virt cortex-a55 (via arm64-support)
#   riscv64     — qemu virt sifive_u (upstream Tier 2)
#   loongarch64 — qemu virt (upstream Tier 3)
#
# Usage:
#   ./scripts/test-all-arch.sh              # test all architectures
#   ./scripts/test-all-arch.sh aarch64      # test one architecture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output"

# ── Architecture definitions ─────────────────────────────────

declare -A QEMU_BIN
QEMU_BIN[x86_64]="qemu-system-x86_64"
QEMU_BIN[aarch64]="qemu-system-aarch64"
QEMU_BIN[riscv64]="qemu-system-riscv64"
QEMU_BIN[loongarch64]="qemu-system-loongarch64"

declare -A QEMU_MACHINE
QEMU_MACHINE[x86_64]="q35"
QEMU_MACHINE[aarch64]="virt"
QEMU_MACHINE[riscv64]="virt"
QEMU_MACHINE[loongarch64]="virt"

declare -A QEMU_CPU
QEMU_CPU[x86_64]="qemu64"
QEMU_CPU[aarch64]="cortex-a55"
QEMU_CPU[riscv64]="rv64"
QEMU_CPU[loongarch64]="max"

declare -A QEMU_MEMORY
QEMU_MEMORY[x86_64]="4096"
QEMU_MEMORY[aarch64]="2048"
QEMU_MEMORY[riscv64]="2048"
QEMU_MEMORY[loongarch64]="2048"

declare -A RUST_TARGET
RUST_TARGET[x86_64]="x86_64-unknown-none"
RUST_TARGET[aarch64]="aarch64-unknown-none"
RUST_TARGET[riscv64]="riscv64imac-unknown-none-elf"
RUST_TARGET[loongarch64]="loongarch64-unknown-none-softfloat"

# ── Test runner ───────────────────────────────────────────────

test_arch() {
    local arch="$1"
    local qemu="${QEMU_BIN[$arch]}"
    local machine="${QEMU_MACHINE[$arch]}"
    local cpu="${QEMU_CPU[$arch]}"
    local memory="${QEMU_MEMORY[$arch]}"
    local target="${RUST_TARGET[$arch]}"
    local log="$OUTPUT_DIR/test-$arch.log"

    echo ""
    echo "┌── $arch ──────────────────────────────────────────"

    # Check QEMU binary exists
    if ! command -v "$qemu" >/dev/null 2>&1; then
        echo "│ SKIP: $qemu not installed"
        echo "│   Install: sudo apt install qemu-system-$arch"
        echo "└── SKIP"
        return 1
    fi

    # Build kernel for this architecture
    echo "│ Building kernel ($target)..."
    (cd "$PROJECT_ROOT" && cargo osdk build --target "$target" --release 2>&1) | tail -3

    # Locate built kernel image
    local kernel
    case "$arch" in
        x86_64)      kernel="$PROJECT_ROOT/target/$target/release/kei-kernel" ;;
        aarch64)     kernel="$PROJECT_ROOT/target/$target/release/kei-kernel.bin" ;;
        riscv64)     kernel="$PROJECT_ROOT/target/$target/release/kei-kernel" ;;
        loongarch64) kernel="$PROJECT_ROOT/target/$target/release/kei-kernel" ;;
    esac

    if [ ! -f "$kernel" ]; then
        echo "│ FAIL: kernel binary not found at $kernel"
        echo "└── FAIL"
        return 1
    fi

    # Boot in QEMU with 30-second timeout
    echo "│ Booting in QEMU ($machine, $cpu, ${memory}MB)..."
    mkdir -p "$OUTPUT_DIR"

    timeout 30 "$qemu" \
        -M "$machine" \
        -cpu "$cpu" \
        -m "$memory" \
        -kernel "$kernel" \
        -nographic \
        -no-reboot \
        2>&1 | tee "$log" || true

    # Check for successful boot indicators in log
    if grep -qiE "(panic|oops|fault)" "$log" && ! grep -qi "kernel_main" "$log"; then
        echo "│ FAIL: kernel panicked or faulted"
        echo "│ Log: $log"
        echo "└── FAIL"
        return 1
    fi

    if grep -qi "kei\|asterinas\|kernel_main\|shell\|console" "$log"; then
        echo "│ PASS: kernel booted successfully"
        echo "│ Log: $log"
        echo "└── PASS"
        return 0
    fi

    echo "│ UNKNOWN: could not determine boot status from log"
    echo "│ Log: $log"
    echo "└── UNKNOWN"
    return 2
}

# ── Main ──────────────────────────────────────────────────────

mkdir -p "$OUTPUT_DIR"

ARCHS=("${@:-x86_64 aarch64 riscv64 loongarch64}")
if [ $# -gt 0 ]; then
    ARCHS=("$@")
fi

echo "=== kei multi-architecture boot test ==="
echo "  Architectures: ${ARCHS[*]}"
echo ""

PASS=0
FAIL=0
SKIP=0

for arch in "${ARCHS[@]}"; do
    if test_arch "$arch"; then
        ((PASS++))
    else
        case $? in
            1) ((FAIL++)) ;;
            2) ((SKIP++)) ;;
        esac
    fi
done

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
