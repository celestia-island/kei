#!/usr/bin/env bash
# update_sdcard_kernel.sh — refresh kei boot artifacts on an EXISTING SD card
# (or card image) in place, WITHOUT rebuilding/reflashing the whole image.
#
# This is the offline alternative to TFTP netboot (see boot.cmd): use it when
# the board is not wired to the build LAN, or to update boot.scr/armbianEnv.txt
# which netboot cannot update (they live on the card itself).
#
# Usage:
#   scripts/update_sdcard_kernel.sh --image target/output/nanopi-r3s/sdcard.img
#   scripts/update_sdcard_kernel.sh --device /dev/sdX        # whole card; uses partition 1
#   scripts/update_sdcard_kernel.sh --device /dev/sdX1       # explicit partition
#
# Requires root for loop/device mounts (via sudo). Only the /boot files are
# replaced; the GPT and U-Boot area are never touched.
set -euo pipefail

BOARD="${BOARD:-nanopi-r3s}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${PROJECT_ROOT}/target/output/${BOARD}"
BOOT_PART_OFFSET=$((32768 * 512))   # LBA 32768 × 512 — keep in sync with make_sdcard.py

MODE=""
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        --image)  MODE="image";  TARGET="$2"; shift 2 ;;
        --device) MODE="device"; TARGET="$2"; shift 2 ;;
        *) echo "usage: $0 [--image sdcard.img | --device /dev/sdX[N]]" >&2; exit 1 ;;
    esac
done
if [ -z "${MODE}" ]; then
    echo "usage: $0 [--image sdcard.img | --device /dev/sdX[N]]" >&2
    exit 1
fi

INITRAMFS="${PROJECT_ROOT}/tests/initramfs/build/initramfs.cpio.gz"
if [ ! -f "${INITRAMFS}" ]; then
    INITRAMFS="${PROJECT_ROOT}/tests/initramfs/build/initramfs_aarch64.cpio.gz"
fi

for f in "${OUT_DIR}/kei-kernel.bin" "${OUT_DIR}/board.dtb" "${INITRAMFS}"; do
    if [ ! -f "${f}" ]; then
        echo "error: missing artifact: ${f}" >&2
        echo "hint: run 'python3 scripts/build.py ${BOARD}' first" >&2
        exit 1
    fi
done

# Recompile boot.scr from the current boot.cmd so script changes propagate.
BOOT_SCR="${OUT_DIR}/boot.scr"
if command -v mkimage >/dev/null 2>&1; then
    mkimage -C none -A arm -T script \
        -d "${PROJECT_ROOT}/configs/board/${BOARD}/boot.cmd" "${BOOT_SCR}" >/dev/null
    echo "[kei] boot.scr recompiled from configs/board/${BOARD}/boot.cmd"
else
    echo "[kei] warning: mkimage not found — keeping existing boot.scr" >&2
fi

MNT="$(mktemp -d)"
cleanup() {
    sync
    sudo umount "${MNT}" >/dev/null 2>&1 || true
    rmdir "${MNT}" 2>/dev/null || true
}
trap cleanup EXIT

if [ "${MODE}" = "image" ]; then
    echo "[kei] mounting ${TARGET} (partition offset ${BOOT_PART_OFFSET})"
    sudo mount -o "loop,offset=${BOOT_PART_OFFSET}" "${TARGET}" "${MNT}"
else
    # Resolve whole-disk devices to their first partition:
    #   /dev/sdX → /dev/sdX1, /dev/mmcblkN / /dev/nvmeNnN → ...p1
    PART=""
    for candidate in "${TARGET}1" "${TARGET}p1" "${TARGET}"; do
        if [ -b "${candidate}" ]; then
            PART="${candidate}"
            break
        fi
    done
    if [ -z "${PART}" ]; then
        echo "error: no usable block device found for ${TARGET}" >&2
        exit 1
    fi
    echo "[kei] mounting ${PART}"
    sudo mount "${PART}" "${MNT}"
fi

# Safety gate: never write to a partition that does not look like a kei
# boot partition — protects against accidentally targeting a system disk.
if [ ! -f "${MNT}/boot/kei-kernel.bin" ]; then
    echo "error: target does not look like a kei boot partition" >&2
    echo "       (no boot/kei-kernel.bin found; refusing to write)" >&2
    exit 1
fi

sudo cp -f "${OUT_DIR}/kei-kernel.bin" "${MNT}/boot/kei-kernel.bin"
sudo cp -f "${OUT_DIR}/board.dtb"      "${MNT}/boot/board.dtb"
sudo cp -f "${INITRAMFS}"              "${MNT}/boot/initramfs.cpio.gz"
[ -f "${BOOT_SCR}" ] && sudo cp -f "${BOOT_SCR}" "${MNT}/boot/boot.scr"
if [ -f "${OUT_DIR}/armbianEnv.txt" ]; then
    echo "[kei] note: overwriting card /boot/armbianEnv.txt (netboot/serverip settings)"
    sudo cp -f "${OUT_DIR}/armbianEnv.txt" "${MNT}/boot/armbianEnv.txt"
fi

echo "[kei] card updated — kernel, DTB, initramfs$( [ -f "${BOOT_SCR}" ] && echo ", boot.scr" )"
echo "[kei] safe to eject and boot the board"
