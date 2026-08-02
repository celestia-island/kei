#!/usr/bin/env bash
# push_netboot.sh — copy kei boot artifacts to a TFTP server directory.
#
# After the one-time SD flash (scripts/make_sdcard.py), all further kernel
# iterations go over the network: rebuild → push → reset the board.
# The board must boot with kei_netboot=1 (see configs/board/*/armbianEnv.txt).
#
# Usage:
#   scripts/push_netboot.sh                            # copy to ${KEI_TFTP_ROOT}/kei/
#   KEI_TFTP_ROOT=/srv/tftp scripts/push_netboot.sh
#   KEI_TFTP_DEST=lab@192.168.2.74:/srv/tftp scripts/push_netboot.sh   # remote via rsync/ssh
set -euo pipefail

BOARD="${BOARD:-nanopi-r3s}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${PROJECT_ROOT}/target/output/${BOARD}"
PREFIX="${KEI_TFTP_PREFIX:-kei}"

INITRAMFS="${PROJECT_ROOT}/tests/initramfs/build/initramfs.cpio.gz"
if [ ! -f "${INITRAMFS}" ]; then
    INITRAMFS="${PROJECT_ROOT}/tests/initramfs/build/initramfs_aarch64.cpio.gz"
fi

# source_path:dest_name — destination names MUST match what boot.cmd fetches.
ARTIFACTS=(
    "${OUT_DIR}/kei-kernel.bin:kei-kernel.bin"
    "${OUT_DIR}/board.dtb:board.dtb"
    "${INITRAMFS}:initramfs.cpio.gz"
)

for pair in "${ARTIFACTS[@]}"; do
    src="${pair%%:*}"
    if [ ! -f "${src}" ]; then
        echo "error: missing artifact: ${src}" >&2
        echo "hint: run 'python3 scripts/build.py ${BOARD}' first" >&2
        exit 1
    fi
done

if [ -n "${KEI_TFTP_DEST:-}" ]; then
    # Remote TFTP server over SSH (requires rsync on both ends).
    for pair in "${ARTIFACTS[@]}"; do
        src="${pair%%:*}"; name="${pair##*:}"
        rsync -av --mkpath "${src}" "${KEI_TFTP_DEST%/}/${PREFIX}/${name}"
    done
    echo "[kei] pushed ${#ARTIFACTS[@]} artifacts to ${KEI_TFTP_DEST%/}/${PREFIX}/"
else
    TFTP_ROOT="${KEI_TFTP_ROOT:-/srv/tftp}"
    DEST="${TFTP_ROOT%/}/${PREFIX}"
    if ! mkdir -p "${DEST}" 2>/dev/null; then
        echo "error: cannot create ${DEST}" >&2
        echo "hint: create it first, e.g.:  sudo install -d -o \"${USER}\" ${DEST}" >&2
        echo "  or push to a remote server:  KEI_TFTP_DEST=user@host:/srv/tftp $0" >&2
        exit 1
    fi
    for pair in "${ARTIFACTS[@]}"; do
        src="${pair%%:*}"; name="${pair##*:}"
        if ! cp -f "${src}" "${DEST}/${name}" 2>/dev/null; then
            echo "error: cannot write to ${DEST}" >&2
            echo "hint: fix ownership, e.g.:  sudo chown -R \"${USER}\" ${DEST}" >&2
            exit 1
        fi
    done
    echo "[kei] pushed ${#ARTIFACTS[@]} artifacts to ${DEST}"
fi

cat <<EOF
next steps:
  1. make sure a TFTP server serves that directory
     (e.g. tftpd-hpa with TFTP_DIRECTORY="${KEI_TFTP_ROOT:-/srv/tftp}")
  2. the board's armbianEnv.txt must set kei_netboot=1 and
     serverip=<this host's IP> (shipped default: 192.168.2.74)
  3. reset the board — U-Boot fetches kei over TFTP and falls
     back to the SD card copy if TFTP is unreachable
EOF
