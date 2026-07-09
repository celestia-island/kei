#!/bin/bash
# Launch QEMU aarch64 in background, serial to log file, SSH on port 2222.
# Usage: bash run_vm.sh
KEI="/mnt/d/源代码/工程项目/celestia/kei"
LOG="/tmp/qemu_serial.log"
PIDFILE="/tmp/qemu.pid"

# Kill any existing instance
kill $(cat "$PIDFILE" 2>/dev/null) 2>/dev/null
pkill -9 -f qemu-system-aarch64 2>/dev/null
sleep 1

# Start QEMU
setsid qemu-system-aarch64 \
    -cpu cortex-a72 -machine virt,gic-version=3,virtualization=on \
    -m 2G -smp 1 --no-reboot \
    -display none \
    -serial file:"$LOG" \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-device,netdev=net0 \
    -kernel "$KEI"/target/osdk/aster-kernel/aster-kernel-osdk-bin.img \
    -initrd "$KEI"/test/initramfs/build/initramfs_aarch64.cpio.gz \
    -append "init=/init" &

echo $! > "$PIDFILE"
echo "QEMU started, PID=$(cat $PIDFILE)"
echo "Serial log: $LOG"
echo "SSH: ssh -i /tmp/client_ssh_key -p 2222 root@127.0.0.1"
