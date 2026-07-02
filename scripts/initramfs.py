#!/usr/bin/env python3
"""kei — create initramfs for kernel build and boot.

The initramfs is required by `cargo osdk build` (referenced in OSDK.toml).
Asterinas's own initramfs uses Nix (heavyweight); this script creates a
lightweight, reproducible alternative.

VDSO note:
  The vDSO module is cfg-gated to x86_64 and riscv64 only
  (kernel/src/lib.rs: #[cfg(any(target_arch = "x86_64", target_arch = "riscv64"))] mod vdso).
  For aarch64, the entire module is excluded — no prebuilt .so files needed.
  The Makefile's unconditional `check_vdso` target is an upstream design issue
  we sidestep by creating the initramfs directly.

Usage:
    python3 scripts/initramfs.py [--arch aarch64] [--force]
"""
from __future__ import annotations

import gzip
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "utils"))
import cli_format as cf

PROJECT_ROOT = Path(__file__).resolve().parent.parent
INITRAMFS_BUILD_DIR = PROJECT_ROOT / "test" / "initramfs" / "build"
INITRAMFS_GZ = INITRAMFS_BUILD_DIR / "initramfs.cpio.gz"

# Init script — runs as PID 1 inside the booted kernel.
INIT_SCRIPT = """#!/bin/sh

mount -t proc none /proc 2>/dev/null
mount -t sysfs none /sys 2>/dev/null
mount -t devtmpfs none /dev 2>/dev/null

echo ""
echo "=== kei ignition ==="
echo "Kernel booted successfully"
echo ""

# Detect network interfaces (the ignition test checks for these)
echo "Network interfaces:"
for iface in /sys/class/net/*; do
    [ -d "$iface" ] || continue
    name=$(basename "$iface")
    mac=$(cat "$iface/address" 2>/dev/null || echo "??:??:??:??:??:??")
    echo "  $name  mac=$mac"
done
echo ""

# Bring up loopback + all ethernet interfaces
if command -v ip >/dev/null 2>&1; then
    ip link set lo up 2>/dev/null
    for iface in /sys/class/net/*; do
        name=$(basename "$iface")
        [ "$name" = "lo" ] && continue
        ip link set "$name" up 2>/dev/null
        echo "  brought up $name"
    done
fi

echo ""
echo "Boot complete."
exec /bin/sh
"""


def create_initramfs(arch: str, force: bool = False) -> Path:
    """Create a minimal initramfs.cpio.gz for kernel boot."""
    if INITRAMFS_GZ.exists() and not force:
        cf.ok(f"initramfs exists ({INITRAMFS_GZ.stat().st_size} bytes)")
        return INITRAMFS_GZ

    INITRAMFS_BUILD_DIR.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="kei-initramfs-") as tmp:
        root = Path(tmp)

        # Directory structure
        for d in ("bin", "dev", "proc", "sys", "etc", "tmp", "run"):
            (root / d).mkdir(parents=True, exist_ok=True)

        # Init script (PID 1)
        init = root / "init"
        init.write_text(INIT_SCRIPT)
        init.chmod(0o755)

        # Include busybox if available (for shell + network tools)
        busybox = shutil.which("busybox")
        if busybox:
            shutil.copy2(busybox, root / "bin" / "busybox")
            for applet in ("sh", "ls", "cat", "ip", "mount", "echo",
                           "sleep", "ifconfig", "udhcpc", "ping"):
                link = root / "bin" / applet
                if not link.exists():
                    link.symlink_to("busybox")
            cf.ok("busybox included")
        else:
            cf.warn("busybox not found — minimal shell only")

        # Build cpio.gz
        cf.pending("creating cpio archive...")
        result = subprocess.run(
            ["sh", "-c", "find . | cpio -H newc -o"],
            cwd=root,
            capture_output=True,
        )
        if result.returncode != 0 or not result.stdout:
            cf.fail("cpio creation failed")
            cf.info(result.stderr.decode("utf-8", errors="replace"))
            return INITRAMFS_GZ

        with gzip.open(INITRAMFS_GZ, "wb") as f:
            f.write(result.stdout)

    size = INITRAMFS_GZ.stat().st_size
    cf.ok(f"initramfs created: {INITRAMFS_GZ.name} ({size} bytes)")
    return INITRAMFS_GZ


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Create initramfs for kei")
    parser.add_argument("--arch", default="aarch64")
    parser.add_argument("--force", action="store_true",
                        help="Rebuild even if initramfs exists")
    args = parser.parse_args()

    cf.section(f"kei initramfs ({args.arch})")
    create_initramfs(args.arch, args.force)
    cf.blank()
    cf.ok("Ready for: cargo osdk build --target-arch " + args.arch)
    return 0


if __name__ == "__main__":
    sys.exit(main())
