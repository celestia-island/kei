#!/bin/bash
# Launch the kei x86_64 kernel (Linux bzImage) under the Windows QEMU binary
# with the microvm machine, mirroring the inlined microvm scheme in OSDK.toml.
#
# Usage:
#   bash scripts/run_x86_64_qemu.sh [SECS]     # default 120 seconds
#
# Serial output is written to target/qemu_x86_64_serial.log and printed at
# the end. QEMU always runs under `timeout` so it can never hang the caller.
#
# NOTE: Windows QEMU cannot open files under non-ASCII (e.g. CJK) paths —
# both -kernel/-initrd and the file: chardev fail with "open ... failed".
# The kernel, initrd and serial log are therefore staged in an ASCII-only
# temporary directory, and the serial log is copied back into target/ after
# the run.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KERNEL="$ROOT/target/osdk/aster-kernel/aster-kernel-osdk-bin"
INITRD="$ROOT/tests/initramfs/build/initramfs.cpio.gz"
LOG="$ROOT/target/qemu_x86_64_serial.log"
QEMU_BIN="qemu-system-x86_64"
if ! command -v "$QEMU_BIN" &>/dev/null; then
    QEMU_BIN="/c/Program Files/qemu/qemu-system-x86_64.exe"
fi
SECS="${1:-120}"

for f in "$KERNEL" "$INITRD"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing $f"
        echo "Build first: cargo osdk build --scheme microvm --target-arch x86_64"
        exit 1
    fi
done
mkdir -p "$ROOT/target"

# Stage into an ASCII-only directory (see the NOTE above). TMPDIR overrides
# the Windows %TMP%/%TEMP% when set.
STAGE_POSIX="$(cygpath "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}")/kei_x64_qemu"
if LC_ALL=C grep -q '[^ -~]' <<<"$STAGE_POSIX"; then
    echo "ERROR: staging path is not ASCII-only: $STAGE_POSIX"
    echo "Set TMPDIR to an ASCII-only directory and retry."
    exit 1
fi
mkdir -p "$STAGE_POSIX"
cp -f "$KERNEL" "$STAGE_POSIX/bzImage"
cp -f "$INITRD" "$STAGE_POSIX/initramfs.cpio.gz"
: > "$STAGE_POSIX/serial.log"

WINKERNEL=$(cygpath -w "$STAGE_POSIX/bzImage")
WININITRD=$(cygpath -w "$STAGE_POSIX/initramfs.cpio.gz")
WINLOG=$(cygpath -w "$STAGE_POSIX/serial.log")

echo "[run-x86_64] kernel: $KERNEL"
echo "[run-x86_64] initrd: $INITRD"
echo "[run-x86_64] staging: $STAGE_POSIX"
echo "[run-x86_64] serial log: $LOG (running ${SECS}s)"

# MSYS_NO_PATHCONV=1 keeps Git Bash from mangling the -append cmdline.
MSYS_NO_PATHCONV=1 timeout --signal=KILL "$SECS" "$QEMU_BIN" \
    -cpu Icelake-Server,+x2apic \
    -machine microvm,rtc=on \
    -nodefaults \
    -no-user-config \
    -m "${MEM:-2G}" \
    -smp "${SMP:-1}" \
    --no-reboot \
    -display none \
    -kernel "$WINKERNEL" \
    -initrd "$WININITRD" \
    -append "SHELL=/bin/sh LOGNAME=root HOME=/ USER=root PATH=/bin:/sbin init=/init -- sh -l" \
    -serial file:"$WINLOG" \
    -monitor none \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -device virtio-keyboard-device \
    -netdev user,id=net0,hostfwd=tcp::2223-:22 \
    -device virtio-net-device,netdev=net0
RC=$?

cp -f "$STAGE_POSIX/serial.log" "$LOG" 2>/dev/null || true

echo "[run-x86_64] qemu exited with code $RC (124/137 = timeout reached)"
echo "===== serial log ====="
cat "$LOG" 2>/dev/null || echo "(no serial output captured)"
