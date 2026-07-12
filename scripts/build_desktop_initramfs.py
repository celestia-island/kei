#!/usr/bin/env python3
"""Build per-architecture initramfs containing the kei_desktop binary.

For each target architecture, produces a newc-format cpio.gz where:
  /init  = the kei_desktop ELF (kernel execve's it directly, DIRECT_INIT)
  /dev, /proc, /sys, /tmp, /etc dirs exist

No busybox/sh is required: kei_desktop is the init and writes to /dev/fb0
directly. This avoids the musl/TLS crashes that busybox triggers on kei.

Usage:
    python3 build_desktop_initramfs.py aarch64
    python3 build_desktop_initramfs.py riscv64
    python3 build_desktop_initramfs.py x86_64
    python3 build_desktop_initramfs.py all      # build all three
"""
import os
import sys
import gzip
import shutil
import tempfile

KEI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARIS = os.path.join(os.path.dirname(KEI), "aris")
BUILD_DIR = os.path.join(KEI, "tests", "initramfs", "build")
sys.path.insert(0, os.path.join(KEI, "tests", "initramfs"))
from build_aarch64_cpio import build  # noqa: E402

# Map architecture -> (aris cargo target triple, output suffix).
ARCHES = {
    "aarch64": "aarch64-unknown-linux-musl",
    "riscv64": "riscv64gc-unknown-linux-musl",
    "x86_64": "x86_64-unknown-linux-musl",
}


def build_one(arch: str) -> str:
    triple = ARCHES[arch]
    bin_path = os.path.join(ARIS, "target", triple, "release", "kei_desktop")
    if not os.path.exists(bin_path):
        print(f"[err] {arch}: binary not found: {bin_path}")
        print(f"      build it first: cd aris && cargo +stable build --release "
              f"-p aris-render --target {triple} --no-default-features "
              f"--features fbdev --bin kei_desktop")
        return ""

    sz = os.path.getsize(bin_path)
    print(f"[{arch}] binary: {bin_path} ({sz} bytes)")

    with tempfile.TemporaryDirectory(prefix=f"kei-rootfs-{arch}-") as rootfs:
        for d in ("bin", "dev", "proc", "sys", "tmp", "root", "etc"):
            os.makedirs(os.path.join(rootfs, d), exist_ok=True)
        # /init IS the render binary (DIRECT_INIT). Kernel execve's it directly.
        init_path = os.path.join(rootfs, "init")
        shutil.copy2(bin_path, init_path)
        os.chmod(init_path, 0o755)
        print(f"[{arch}] DIRECT_INIT: /init = kei_desktop ELF")
        # minimal /etc/passwd + group (some libc init paths read these)
        with open(os.path.join(rootfs, "etc", "passwd"), "w") as f:
            f.write("root:x:0:0:root:/root:/bin/sh\n")
        with open(os.path.join(rootfs, "etc", "group"), "w") as f:
            f.write("root:x:0:\n")

        out_name = f"initramfs_desktop_{arch}.cpio.gz"
        out_path = os.path.join(BUILD_DIR, out_name)
        build(rootfs, out_path)
        print(f"[{arch}] wrote {out_path} ({os.path.getsize(out_path)} bytes)")
        return out_path


def main():
    os.makedirs(BUILD_DIR, exist_ok=True)
    args = sys.argv[1:] or ["all"]
    if "all" in args:
        args = list(ARCHES.keys())
    ok = []
    for arch in args:
        if arch not in ARCHES:
            print(f"[err] unknown arch: {arch}; choices: {list(ARCHES)}")
            continue
        out = build_one(arch)
        if out:
            ok.append(out)
    print("---")
    print(f"built {len(ok)} initramfs image(s):")
    for o in ok:
        print(f"  {o}")


if __name__ == "__main__":
    main()
