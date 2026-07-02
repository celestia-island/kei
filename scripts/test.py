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
    output_dir = PROJECT_ROOT / "output" / board
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

    cmd = [qemu, "-M", "virt", "-cpu", "cortex-a55", "-m", "2048", "-smp", "4"]
    cmd.extend(["-kernel", str(kernel)])
    if dtb.exists():
        cmd.extend(["-dtb", str(dtb)])
    cmd.extend(["-nographic", "-no-reboot"])

    result = subprocess.run(cmd)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
