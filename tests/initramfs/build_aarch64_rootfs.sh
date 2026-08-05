#!/bin/bash
# Builds the aarch64 dropbear initramfs rootfs directory.
# Run on the Linux host: bash build_aarch64_rootfs.sh
#
# Requires:
#   - aarch64 musl cross toolchain (musl.cc aarch64-linux-musl-cross), or
#     AR/RANLIB/CC env vars pointing at aarch64 musl tools.
#   - dropbear source at $DROPBEAR_SRC (default /tmp/dropbear-2022.83), or
#     prebuilt static dropbear/dropbearkey binaries at $DROPBEAR_DIR.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOTFS=/tmp/aarch64-rootfs
DROPBEAR_SRC="${DROPBEAR_SRC:-/tmp/dropbear-2022.83}"
DROPBEAR_DIR="${DROPBEAR_DIR:-}"
MUSL_BIN="${MUSL_BIN:-/tmp/aarch64-linux-musl-cross/bin}"

# ---------------------------------------------------------------- toolchain

if [ -z "$DROPBEAR_DIR" ]; then
    if [ ! -d "$DROPBEAR_SRC" ]; then
        echo "[aarch64-rootfs] dropbear source missing at $DROPBEAR_SRC"
        echo "  get it: curl -L -o /tmp/db.tgz https://github.com/mkj/dropbear/archive/refs/tags/DROPBEAR_2022.83.tar.gz && tar -xzf /tmp/db.tgz -C /tmp && mv /tmp/dropbear-DROPBEAR_2022.83 $DROPBEAR_SRC"
        exit 1
    fi
    export PATH="$MUSL_BIN:$PATH"
    export AR="${AR:-aarch64-linux-musl-ar}"
    export RANLIB="${RANLIB:-aarch64-linux-musl-ranlib}"
    export CC="${CC:-aarch64-linux-musl-gcc}"
    if ! command -v "$CC" >/dev/null 2>&1; then
        echo "[aarch64-rootfs] musl cross compiler not found ($CC); get it from https://musl.cc (aarch64-linux-musl-cross.tgz) and set MUSL_BIN"
        exit 1
    fi
fi

# ---------------------------------------------------------------- rootfs

rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"/{bin,sbin,etc/dropbear,dev,proc,sys,tmp,root/.ssh,run,var/log}

# busybox
cp "$KEI_ROOT"/tests/initramfs/busybox-aarch64 "$ROOTFS"/bin/busybox
chmod +x "$ROOTFS"/bin/busybox

# busybox applet symlinks
cd "$ROOTFS"/bin
APPLETS="sh echo cat ls mount ip ifconfig sleep ps kill mkdir rm cp mv ln chmod chown id uname hostname pwd env true false test head tail wc grep sed awk vi ping udhcpc date uname whoami reboot poweroff"
for cmd in $APPLETS; do
    ln -sf busybox "$cmd"
done
cd -

# dropbear + dropbearkey
if [ -n "$DROPBEAR_DIR" ]; then
    cp "$DROPBEAR_DIR"/dropbear "$ROOTFS"/sbin/dropbear
    cp "$DROPBEAR_DIR"/dropbearkey "$ROOTFS"/sbin/dropbearkey
else
    (cd "$DROPBEAR_SRC" && make clean >/dev/null 2>&1 || true)
    (cd "$DROPBEAR_SRC" && make -j4 PROGRAMS="dropbear dropbearkey" LDFLAGS="-static -Wl,-z,now -Wl,-z,relro")
    cp "$DROPBEAR_SRC"/dropbear "$ROOTFS"/sbin/dropbear
    cp "$DROPBEAR_SRC"/dropbearkey "$ROOTFS"/sbin/dropbearkey
fi
chmod +x "$ROOTFS"/sbin/dropbear "$ROOTFS"/sbin/dropbearkey

# init script
cp "$SCRIPT_DIR"/src/init_aarch64 "$ROOTFS"/init
chmod +x "$ROOTFS"/init

# config files (dropbear needs getpwnam("root"))
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOTFS"/etc/passwd
printf 'root:x:0:\n' > "$ROOTFS"/etc/group

# authorized_keys (if a client key was generated)
if [ -f /tmp/client_ssh_key.pub ]; then
    cp /tmp/client_ssh_key.pub "$ROOTFS"/root/.ssh/authorized_keys
fi

# Pack the initramfs image.
BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"
python3 "$SCRIPT_DIR/build_aarch64_cpio.py" "$ROOTFS" "$BUILD_DIR/initramfs_aarch64_dropbear.cpio.gz"
echo "=== initramfs ready at $BUILD_DIR/initramfs_aarch64_dropbear.cpio.gz ==="
echo "Boot it with: qemu-system-aarch64 -M virt,gic-version=3,virtualization=on -cpu cortex-a72 -m 1024 -kernel <kei.bin> -initrd $BUILD_DIR/initramfs_aarch64_dropbear.cpio.gz -append 'console=ttyAMA0 init=/init' -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-device,netdev=n0"
echo "Then: ssh -i /tmp/client_ssh_key -p 2222 root@127.0.0.1"
