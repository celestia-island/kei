#!/usr/bin/env python3
"""kei — boot kernel in QEMU for a specific board.

Usage:
    python3 scripts/test.py [board]
    python3 scripts/test.py nanopi-r3s
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "utils"))
import cli_format as cf

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="QEMU boot test for a board")
    parser.add_argument("board", nargs="?", default="nanopi-r3s")
    args = parser.parse_args()

    board = args.board
    output_dir = PROJECT_ROOT / "target" / "output" / board
    kernel = output_dir / "kei-kernel.bin"
    dtb = output_dir / "board.dtb"

    if not kernel.exists():
        cf.fail(f"Kernel not found: {kernel}")
        cf.info("  Run: python3 scripts/build.py " + board)
        return 1

    qemu = shutil.which("qemu-system-aarch64")
    if not qemu:
        cf.fail("qemu-system-aarch64 not installed")
        return 1

    cf.section(f"kei smoke test: {board}")
    cf.info("Press Ctrl-A X to exit.")
    cf.blank()

    # The kei aarch64 kernel requires EL2 boot (virtualization=on) and
    # GICv3 for interrupt handling.
    cmd = [qemu, "-M", "virt,gic-version=3,virtualization=on", "-cpu", "cortex-a72", "-m", "2048", "-smp", "1"]
    # Attach initramfs if available
    initramfs = PROJECT_ROOT / "test" / "initramfs" / "build" / "initramfs.cpio.gz"
    cmd.extend(["-kernel", str(kernel)])
    if initramfs.exists():
        cmd.extend(["-initrd", str(initramfs)])
    if dtb.exists():
        cmd.extend(["-dtb", str(dtb)])
    cmd.extend(["-nographic", "-no-reboot"])

    result = subprocess.run(cmd)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
