#!/usr/bin/env python3
"""kei — build kernel for target board.

Usage:
    python3 scripts/build.py [board] [profile]
    python3 scripts/build.py nanopi-r3s
    python3 scripts/build.py nanopi-r3s release
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

sys.path.insert(0, str(Path(__file__).parent / "utils"))
import cli_format as cf

PROJECT_ROOT = Path(__file__).resolve().parent.parent

ARCH_TO_TARGET = {
    "x86_64": "x86_64-unknown-none",
    "aarch64": "aarch64-unknown-none",
    "riscv64": "riscv64imac-unknown-none-elf",
    "loongarch64": "loongarch64-unknown-none-softfloat",
}


def load_board_config(board: str) -> dict:
    config_path = PROJECT_ROOT / "configs" / f"{board}.toml"
    if not config_path.exists():
        cf.warn(f"Config not found: {config_path}, using defaults")
        return {"board": {"name": board, "arch": "aarch64"},
                "kernel": {"bsp_crate": "bsp-rk3566"}}
    with config_path.open("rb") as f:
        return tomllib.load(f)


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Build kei kernel")
    parser.add_argument("board", nargs="?", default="nanopi-r3s")
    parser.add_argument("profile", nargs="?", default="release")
    args = parser.parse_args()

    board = args.board
    profile = args.profile
    config = load_board_config(board)

    board_cfg = config.get("board", {})
    arch = board_cfg.get("arch", "aarch64")
    rust_target = ARCH_TO_TARGET.get(arch)
    if not rust_target:
        cf.fail(f"Unknown arch: {arch}")
        return 1

    output_dir = PROJECT_ROOT / "output" / board
    output_dir.mkdir(parents=True, exist_ok=True)

    cf.section(f"kei build: {board} ({profile})")

    # Verify kei tree is populated
    if not (PROJECT_ROOT / "ostd").exists():
        cf.fail("kei tree not populated (ostd/ missing)")
        cf.info("  Run: just vendor && just pull-arm64")
        return 1

    cf.blank()
    cf.step("[1/5] Board config loaded")
    cf.info(f"  Target: {rust_target}")
    cf.info(f"  Arch:   {arch}")

    # Ensure initramfs exists (cargo osdk build requires it)
    cf.blank()
    cf.step("[2/5] Preparing initramfs")
    initramfs_script = PROJECT_ROOT / "scripts" / "initramfs.py"
    subprocess.run(
        [sys.executable, str(initramfs_script), "--arch", arch],
        check=False,
    )

    cf.blank()
    cf.step("[3/5] Building kernel via cargo osdk")
    result = subprocess.run(
        ["cargo", "osdk", "build", "--target-arch", arch, "--profile", profile],
        cwd=PROJECT_ROOT,
    )
    if result.returncode != 0:
        cf.fail("Kernel build failed")
        cf.info("  TIP: verify ostd/src/arch/aarch64/ exists")
        return 1

    cf.blank()
    cf.step("[4/5] Copying build artifacts")
    kernel_paths = [
        PROJECT_ROOT / "target" / rust_target / profile / "kei-kernel",
        PROJECT_ROOT / "target" / rust_target / profile / "kei-kernel.bin",
    ]
    copied = False
    for kp in kernel_paths:
        if kp.exists():
            shutil.copy2(kp, output_dir / "kei-kernel.bin")
            cf.ok(f"  Kernel: {output_dir / 'kei-kernel.bin'}")
            copied = True
            break
    if not copied:
        cf.warn("  Kernel binary not found at expected paths")

    cf.blank()
    cf.step("[5/5] Compiling device tree")
    dtc = shutil.which("dtc")
    dtb_name = config.get("kernel", {}).get("dtb", "")
    if dtc and dtb_name:
        dtb_src = PROJECT_ROOT / "board" / board / "device-tree"
        dts_files = list(dtb_src.glob("*.dts")) if dtb_src.exists() else []
        if dts_files:
            subprocess.run(
                ["dtc", "-I", "dts", "-O", "dtb",
                 "-o", str(output_dir / "board.dtb"),
                 str(dts_files[0])],
                check=False,
            )
            cf.ok(f"  DTB: {output_dir / 'board.dtb'}")
        else:
            cf.info("  No .dts files found")
    else:
        cf.info("  (dtc not available or no DTB configured — skipping)")

    cf.blank()
    cf.ok(f"Build complete: {output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
