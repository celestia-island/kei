#!/bin/bash
# Build the aarch64 serial-console initramfs (busybox + init, no dropbear)
# at tests/initramfs/build/initramfs_aarch64.cpio.gz — the path referenced
# by [scheme."aarch64".run.boot] in OSDK.toml.
#
# CI counterpart of build_aarch64_rootfs.sh: that script needs a prebuilt
# dropbear tree, which CI does not have; this variant boots to a serial
# console shell like the x86_64 initramfs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ROOTFS="$BUILD_DIR/rootfs_aarch64"
OUT="$BUILD_DIR/initramfs_aarch64.cpio.gz"

BUSYBOX="$SCRIPT_DIR/busybox-aarch64"
if [ ! -f "$BUSYBOX" ]; then
    echo "[aarch64-rootfs] busybox-aarch64 not found, downloading static musl build..."
    curl -fsSL -o "$BUSYBOX" \
        "https://busybox.net/downloads/binaries/1.35.0-aarch64-linux-musl/busybox"
    chmod +x "$BUSYBOX"
fi

rm -rf "$ROOTFS"
mkdir -p "$ROOTFS/bin" "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/etc" "$ROOTFS/tmp"

cp "$BUSYBOX" "$ROOTFS/bin/busybox"
chmod +x "$ROOTFS/bin/busybox"
for applet in sh ls cat mount echo sleep mkdir ip; do
    ln -sf busybox "$ROOTFS/bin/$applet"
done

cp "$SCRIPT_DIR/src/init_aarch64_ci" "$ROOTFS/init"
chmod +x "$ROOTFS/init"

# Minimal user database so `id`/`login` lookups do not fail.
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$ROOTFS/etc/passwd"
printf 'root:x:0:\n' > "$ROOTFS/etc/group"

mkdir -p "$BUILD_DIR"
python3 "$SCRIPT_DIR/build_aarch64_cpio.py" "$ROOTFS" "$OUT"
echo "[aarch64-rootfs] wrote $OUT ($(stat -c%s "$OUT") bytes)"
