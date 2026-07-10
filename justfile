# kei — build & run commands
# Usage: just <recipe>
#
# Quick start (aarch64):
#   just setup-keys   # generate SSH keys (one-time)
#   just run          # build + launch QEMU with SDL window
#
# For other architectures:
#   just run aarch64
#   just run x86_64
#   just run riscv64

set unstable
set shell := ["bash", "-c"]
# On Windows, use Git Bash (not WSL) for simple recipes. Recipes that need
# WSL (like _build-aarch64) call `wsl` explicitly.
set windows-shell := ["bash.exe", "-c"]
set lists

import "./celestia-devtools.just"

default: list-arch

# ── Environment ─────────────────────────────────────────────

# Inspect the build environment: host kind, WSL2 distros (on Windows),
# selected distro, and container backend. Pre-flight check before build.
env-check:
    {{python_cmd}} scripts/check_env.py

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

# ── SSH Keys (aarch64) ──────────────────────────────────────
#
# dropbear uses public-key auth only (no password). Generate the
# client keypair and embed the public key into the initramfs.

# Generate an ed25519 SSH keypair for VM access (one-time setup).
# The private key is saved to test/initramfs/build/client_ssh_key.
setup-keys:
    #!/usr/bin/env bash
    set -e
    KEYDIR="test/initramfs/build"
    mkdir -p "$KEYDIR"
    if [ -f "$KEYDIR/client_ssh_key" ]; then
        echo "SSH key already exists at $KEYDIR/client_ssh_key"
    else
        ssh-keygen -t ed25519 -N "" -C "kei@aarch64" \
            -f "$KEYDIR/client_ssh_key"
        echo "Generated SSH keypair:"
        echo "  Private: $KEYDIR/client_ssh_key"
        echo "  Public:  $KEYDIR/client_ssh_key.pub"
    fi
    # Also copy to /tmp for the rootfs build scripts
    cp "$KEYDIR/client_ssh_key.pub" /tmp/client_ssh_key.pub 2>/dev/null || true

# Show SSH connection instructions for the running VM.
ssh-info:
    @echo ""
    @echo "╔══════════════════════════════════════════════════════════════╗"
    @echo "║                    SSH Connection Info                       ║"
    @echo "╠══════════════════════════════════════════════════════════════╣"
    @echo "║  Host:     127.0.0.1                                         ║"
    @echo "║  Port:     2222                                              ║"
    @echo "║  User:     root                                              ║"
    @echo "║  Auth:     public-key (ed25519)                              ║"
    @echo "║  Key:      test/initramfs/build/client_ssh_key               ║"
    @echo "╠══════════════════════════════════════════════════════════════╣"
    @echo "║  Connect:                                                    ║"
    @echo "║    ssh -i test/initramfs/build/client_ssh_key \\             ║"
    @echo "║        -o StrictHostKeyChecking=no -p 2222 root@127.0.0.1    ║"
    @echo "╚══════════════════════════════════════════════════════════════╝"
    @echo ""

# ── Build ──────────────────────────────────────────────────

build:
    just cache-guard
    {{python_cmd}} scripts/build.py nanopi-r3s

build-board BOARD:
    just cache-guard
    {{python_cmd}} scripts/build.py {{BOARD}}

# Build the kernel for a specific architecture.
# Usage: just build-arch aarch64  (or x86_64, riscv64, loongarch64)
build-arch ARCH:
    #!/usr/bin/env bash
    set -e
    ARCH="{{ARCH}}"
    case "$ARCH" in
        aarch64)
            just _build-aarch64
            ;;
        x86_64)
            cargo osdk build --target x86_64-unknown-none
            ;;
        riscv64)
            cargo osdk build --scheme riscv --target-arch riscv64
            ;;
        loongarch64)
            cargo osdk build --scheme loongarch --target-arch loongarch64
            ;;
        *)
            echo "Unsupported arch: $ARCH"
            echo "Supported: aarch64, x86_64, riscv64, loongarch64"
            exit 1
            ;;
    esac

# Build aarch64 kernel + ARM64 Image + initramfs (internal).
_build-aarch64:
    #!/usr/bin/env bash
    set -e
    echo "[build] Building aarch64 kernel..."
    wsl -d Ubuntu-24.04 -- bash -lc 'source ~/.cargo/env 2>/dev/null; cd "/mnt/d/源代码/工程项目/celestia/kei" && cargo osdk build --scheme aarch64 --target-arch aarch64' 2>&1 | tail -5
    # Copy ELF if OSDK packaging failed (WSL/9p issue)
    if [ ! -f target/osdk/aster-kernel/aster-kernel-osdk-bin.qemu_elf ]; then
        cp target/osdk/aster-kernel-osdk-bin.qemu_elf target/osdk/aster-kernel/ 2>/dev/null || true
    fi
    # Build ARM64 Image from ELF
    echo "[build] Creating ARM64 Image..."
    wsl -d Ubuntu-24.04 -- bash -c 'python3 "/mnt/d/源代码/工程项目/celestia/kei/tools/make_arm64_image.py" "/mnt/d/源代码/工程项目/celestia/kei/target/osdk/aster-kernel/aster-kernel-osdk-bin.qemu_elf" "/mnt/d/源代码/工程项目/celestia/kei/target/osdk/aster-kernel/aster-kernel-osdk-bin.image" 2>&1 | tail -1'
    echo "[build] Done. Kernel image: target/osdk/aster-kernel/aster-kernel-osdk-bin.image"

# Format Rust + Markdown docs
fmt:
    cargo fmt --all
    just fmt-markdown

fmt-check:
    cargo fmt --all -- --check
    just fmt-markdown --check

check-bsp:
    cd bsp && cargo check

# Build the aarch64 initramfs with dropbear SSH server.
initramfs:
    just setup-keys
    {{python_cmd}} scripts/initramfs.py --arch aarch64

initramfs-force:
    just setup-keys
    {{python_cmd}} scripts/initramfs.py --arch aarch64 --force

# ── Run / Debug ─────────────────────────────────────────────
#
# Launch QEMU for interactive use. The SDL window shows the terminal;
# SSH is available on port 2222 (aarch64 only).
#
# Usage:
#   just run              # aarch64 with SDL window (default)
#   just run aarch64      # explicit arch
#   just run x86_64       # x86_64 (serial console)
#   just run riscv64      # RISC-V (serial console)
#   just run headless     # aarch64 without GUI (SSH only)

# Launch QEMU for a specific architecture with SDL window and SSH.
# Usage: just run [ARCH|headless]
run ARCH="aarch64":
    #!/usr/bin/env bash
    set -e
    ARG="{{ARCH}}"
    if [ "$ARG" = "headless" ]; then
        ARCH="aarch64"
        HEADLESS=1
    else
        ARCH="$ARG"
        HEADLESS=0
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  kei VM — Architecture: $ARCH"
    echo "═══════════════════════════════════════════════════════"
    echo ""

    case "$ARCH" in
        aarch64)
            just _run-aarch64 "$HEADLESS"
            ;;
        x86_64)
            just _run-x86_64
            ;;
        riscv64)
            just _run-riscv64
            ;;
        loongarch64)
            just _run-loongarch64
            ;;
        *)
            echo "Unsupported arch: $ARCH"
            echo "Supported: aarch64, x86_64, riscv64, loongarch64"
            echo "  just run aarch64    — ARM64 with SDL window + SSH"
            echo "  just run x86_64     — x86_64 with serial console"
            echo "  just run riscv64    — RISC-V with serial console"
            echo "  just run headless   — aarch64 without GUI"
            exit 1
            ;;
    esac

# Internal: launch aarch64 QEMU.
_run-aarch64 HEADLESS:
    #!/usr/bin/env bash
    set -e
    HEADLESS="{{HEADLESS}}"

    # Ensure SSH keys exist
    just setup-keys

    # Ensure kernel is built
    if [ ! -f target/osdk/aster-kernel/aster-kernel-osdk-bin.image ]; then
        echo "[run] Kernel image not found, building..."
        just _build-aarch64
    fi

    # Kill any existing QEMU
    taskkill //F //IM qemu-system-aarch64.exe 2>/dev/null || true
    pkill -9 -f qemu-system-aarch64 2>/dev/null || true
    sleep 1

    # Determine display mode
    if [ "$HEADLESS" = "1" ]; then
        DISPLAY_OPT="-display none"
        echo "[run] Headless mode (no GUI window)"
    else
        DISPLAY_OPT="-display sdl"
        echo "[run] SDL window mode (GUI terminal)"
    fi

    echo ""

    # Print SSH info BEFORE launching QEMU
    just ssh-info

    echo "  Serial log: target/qemu_serial.log"
    echo "  Kernel:     target/osdk/aster-kernel/aster-kernel-osdk-bin.image"
    echo ""

    # Convert paths for Windows QEMU
    WINIMAGE=$(cygpath -w "target/osdk/aster-kernel/aster-kernel-osdk-bin.image" 2>/dev/null || echo "target/osdk/aster-kernel/aster-kernel-osdk-bin.image")
    WININITRD=$(cygpath -w "test/initramfs/build/initramfs_aarch64.cpio.gz" 2>/dev/null || echo "test/initramfs/build/initramfs_aarch64.cpio.gz")
    WINLOG=$(cygpath -w "target/qemu_serial.log" 2>/dev/null || echo "target/qemu_serial.log")

    # Launch QEMU detached. nohup + disown keeps it alive after the
    # launching shell (just) exits.
    # MSYS_NO_PATHCONV=1 prevents Git Bash from mangling /init.
    echo "[run] Launching QEMU..."
    MSYS_NO_PATHCONV=1 nohup "/c/Program Files/qemu/qemu-system-aarch64.exe" \
        -cpu cortex-a72 -machine virt,gic-version=3,virtualization=on \
        -m 2G -smp 1 --no-reboot \
        $DISPLAY_OPT \
        -device virtio-gpu-device \
        -device virtio-keyboard-device \
        -serial file:"$WINLOG" \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-device,netdev=net0 \
        -kernel "$WINIMAGE" \
        -initrd "$WININITRD" \
        -append "init=/init SHELL=/bin/sh LOGNAME=root HOME=/ USER=root PATH=/bin:/sbin" \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    echo ""
    echo "  QEMU is running in the background."
    echo "  SSH will be available in ~20s on port 2222"
    echo "  Use 'just ssh' to connect, 'just log' to see boot messages"
    echo "  Use 'just kill' to stop QEMU"

# Internal: launch x86_64 QEMU via cargo osdk run.
_run-x86_64:
    #!/usr/bin/env bash
    set -e
    echo "[run] x86_64 uses 'cargo osdk run' with serial console"
    echo "[run] No SSH server on x86_64 (uses serial shell)"
    echo ""
    cargo osdk run --target x86_64-unknown-none

# Internal: launch RISC-V QEMU via cargo osdk run.
_run-riscv64:
    #!/usr/bin/env bash
    set -e
    echo "[run] RISC-V uses 'cargo osdk run' with serial console"
    echo "[run] No SSH server on RISC-V (uses serial shell)"
    echo ""
    cargo osdk run --scheme riscv --target-arch riscv64

# Internal: launch LoongArch QEMU via cargo osdk run.
_run-loongarch64:
    #!/usr/bin/env bash
    set -e
    echo "[run] LoongArch uses 'cargo osdk run' with serial console"
    echo "[run] No SSH server on LoongArch (uses serial shell)"
    echo ""
    cargo osdk run --scheme loongarch --target-arch loongarch64

# Connect to the running aarch64 VM via SSH.
ssh:
    @echo "Connecting to kei VM via SSH..."
    ssh -i test/initramfs/build/client_ssh_key \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p 2222 root@127.0.0.1

# Stop the running QEMU instance.
kill:
    #!/usr/bin/env bash
    taskkill //F //IM qemu-system-aarch64.exe 2>/dev/null || true
    taskkill //F //IM qemu-system-x86_64.exe 2>/dev/null || true
    taskkill //F //IM qemu-system-riscv64.exe 2>/dev/null || true
    pkill -9 -f qemu-system 2>/dev/null || true
    echo "QEMU stopped."

# Show the serial log (boot messages).
log:
    @tail -50 target/qemu_serial.log 2>/dev/null || echo "No serial log found. Run 'just run' first."

# Watch the serial log in real-time.
log-follow:
    @tail -f target/qemu_serial.log 2>/dev/null || echo "No serial log found."

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

# List all supported architectures and their run commands.
list-arch:
    @echo ""
    @echo "kei supported architectures:"
    @echo ""
    @echo "  aarch64      ARM64 (QEMU virt) — SDL window + SSH"
    @echo "               just run aarch64"
    @echo "               just run            (default)"
    @echo "               just run headless   (no GUI)"
    @echo "               just ssh            (connect)"
    @echo ""
    @echo "  x86_64       x86-64 (QEMU pc) — serial console"
    @echo "               just run x86_64"
    @echo ""
    @echo "  riscv64      RISC-V (QEMU virt) — serial console"
    @echo "               just run riscv64"
    @echo ""
    @echo "  loongarch64  LoongArch (QEMU virt) — serial console"
    @echo "               just run loongarch64"
    @echo ""
    @echo "Other commands:"
    @echo "  just setup-keys    Generate SSH keys (one-time)"
    @echo "  just ssh-info      Show SSH connection details"
    @echo "  just kill          Stop QEMU"
    @echo "  just log           Show boot log"
    @echo "  just log-follow    Follow boot log live"
    @echo ""

clean:
    rm -rf build/ output/
    cargo clean
    rm -f target/qemu_serial.log target/qemu.pid target/client_ssh_key 2>/dev/null || true

dev-shell:
    {{python_cmd}} scripts/dev_shell.py
