#!/bin/bash
# Launch QEMU aarch64 with SDL window display, serial to log file, SSH on port 2222.
# Usage: bash run_vm.sh [headless]
#   (no args)  — SDL window + serial to file
#   headless   — no display (for CI / SSH-only access)
KEI="/mnt/d/源代码/工程项目/celestia/kei"
LOG="/tmp/qemu_serial.log"
PIDFILE="/tmp/qemu.pid"

# Kill any existing instance
kill $(cat "$PIDFILE" 2>/dev/null) 2>/dev/null
pkill -9 -f qemu-system-aarch64 2>/dev/null
sleep 1

DISPLAY_OPT="-display sdl"
if [ "$1" = "headless" ]; then
    DISPLAY_OPT="-display none"
fi

# Start QEMU
setsid qemu-system-aarch64 \
    -cpu cortex-a72 -machine virt,gic-version=3,virtualization=on \
    -m 2G -smp 1 --no-reboot \
    $DISPLAY_OPT \
    -device virtio-gpu-device \
    -device virtio-keyboard-device \
    -serial file:"$LOG" \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-device,netdev=net0 \
    -kernel "$KEI"/target/osdk/aster-kernel/aster-kernel-osdk-bin.img \
    -initrd "$KEI"/test/initramfs/build/initramfs_aarch64.cpio.gz \
    -append "init=/init" &

echo $! > "$PIDFILE"
echo "QEMU started, PID=$(cat $PIDFILE)"
echo "Display: $DISPLAY_OPT"
echo "Serial log: $LOG"
echo "SSH: ssh -i /tmp/client_ssh_key -p 2222 root@127.0.0.1"
