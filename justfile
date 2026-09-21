# kei — build & run commands
# Usage: just <recipe>
#
# Quick start (aarch64):
#   just setup-keys   # generate SSH keys (one-time)
#   just run          # build + launch QEMU with SDL window
#
# For other architectures:
#   just run aarch64
#   just run x86_64
#   just run riscv64

set shell := ["bash", "-c"]
# Windows: PowerShell (the 5.1 floor ships with every Windows; pwsh 7 is
# NOT assumed). Linewise recipes must stay PS-5.1-safe: no `&&` chains,
# `cd X; cmd` instead of `cd X && cmd`. Bash-only recipes use
# [script('bash')] and need Git Bash (or WSL) when actually run.
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command", "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; $PSDefaultParameterValues['*:Encoding']='utf8';"]
set unstable
set lists

# Auto-load .env so ARIS_REPO (and other config) is available in all recipes.
# just >= 1.32 supports this natively; we're on 1.55.
set dotenv-load := true

# Repo definitions override the shared template's (imported above).
set allow-duplicate-recipes
set allow-duplicate-variables

# Path to the aris repository. Override via .env or shell env var.
# Used by build-aris / build-desktop recipes and the initramfs scripts.
ARIS_REPO := env_var_or_default("ARIS_REPO", "../aris")

# Shared celestia-devtools recipes — NOT in git. The imports are optional
# (`import?`) so the justfile still loads before staging, but any recipe that
# references shared variables (e.g. {{python_cmd}}) or devtools recipes needs
# the staged import. Bootstrap once: celestia-devtools init (or `just fetch`
# if already staged). Refresh after upgrades.
import? "./.just/git-bash-interop.just"
import? "./.just/celestia-devtools.just"

# Stage shared celestia-devtools recipes into .just/ (gitignored).
# Source order: explicit URL arg → local pip bundle (offline) → GitHub raw.
# curl honors HTTP_PROXY/HTTPS_PROXY/ALL_PROXY env vars automatically.
fetch URL='':
    {{ if os_family() == "windows" { "python" } else { "python3" } }} -c "import os; os.makedirs('.just', exist_ok=True)"
    {{ if URL != "" { "curl -fsSL " + URL + " -o .just/celestia-devtools.just" } else if which("celestia-devtools") != "" { "celestia-devtools fetch-just" } else { "curl -fsSL https://raw.githubusercontent.com/celestia-island/celestia-devtools/dev/src/celestia_devtools/common.just -o .just/celestia-devtools.just" } }}
default: list-arch

# ── Environment ─────────────────────────────────────────────

# Inspect the build environment: host kind, WSL2 distros (on Windows),
# selected distro, and container backend. Pre-flight check before build.
env-check:
    {{python_cmd}} scripts/check_env.py

# ── Vendoring (Apple LLVM model: pin + periodically absorb) ──

setup:
    {{python_cmd}} scripts/setup.py

# Vendor upstream asterinas into the tree.
#   just vendor          # latest
#   just vendor <ref>    # specific git ref
vendor *ARGS='':
    {{python_cmd}} scripts/vendor_upstream.py {{ARGS}}

# Pull (vendor) upstream code.
#   just pull arm64          # latest arm64 code
#   just pull arm64 <ref>    # specific git ref
[script('python')]
pull target='arm64' *ARGS='':
    import shlex, subprocess, sys
    if "{{target}}" == "arm64":
        cmd = ["{{python_cmd}}", "scripts/pull_arm64.py"] + shlex.split("{{ARGS}}")
        sys.exit(subprocess.run(cmd).returncode)
    else:
        print("unknown pull target: {{target}}", file=sys.stderr)
        print("usage: just pull [arm64]", file=sys.stderr)
        sys.exit(1)

[script('python')]
versions:
    import pathlib
    print("=== Upstream asterinas ===")
    p = pathlib.Path(".vendored-upstream")
    print(p.read_text(encoding="utf-8", errors="replace").strip() if p.exists()
          else "  (not vendored yet — run 'just vendor')")
    print("")
    print("=== ARM64 source ===")
    p = pathlib.Path(".vendored-arm64")
    print(p.read_text(encoding="utf-8", errors="replace").strip() if p.exists()
          else "  (not pulled yet — run 'just pull arm64')")

# ── SSH Keys (aarch64) ──────────────────────────────────────
#
# dropbear uses public-key auth only (no password). Generate the
# client keypair and embed the public key into the initramfs.

# Generate an ed25519 SSH keypair for VM access (one-time setup).
# The private key is saved to tests/initramfs/build/client_ssh_key.
[script('python')]
setup-keys:
    import os, pathlib, shutil, subprocess
    keydir = pathlib.Path("tests/initramfs/build")
    keydir.mkdir(parents=True, exist_ok=True)
    key = keydir / "client_ssh_key"
    if key.exists():
        print(f"SSH key already exists at {keydir}/client_ssh_key")
    else:
        subprocess.run([
            "ssh-keygen", "-t", "ed25519", "-N", "", "-C", "kei@aarch64",
            "-f", str(key),
        ], check=True)
        print("Generated SSH keypair:")
        print(f"  Private: {keydir}/client_ssh_key")
        print(f"  Public:  {keydir}/client_ssh_key.pub")
    # Also copy to /tmp for the rootfs build scripts
    try:
        shutil.copy(str(key) + ".pub", "/tmp/client_ssh_key.pub")
    except OSError:
        pass

# Show SSH connection instructions for the running VM.
ssh-info:
    @echo ""
    @echo "╔══════════════════════════════════════════════════════════════╗"
    @echo "║                    SSH Connection Info                       ║"
    @echo "╠══════════════════════════════════════════════════════════════╣"
    @echo "║  Host:     127.0.0.1                                         ║"
    @echo "║  Port:     2222                                              ║"
    @echo "║  User:     root                                              ║"
    @echo "║  Auth:     public-key (ed25519)                              ║"
    @echo "║  Key:      tests/initramfs/build/client_ssh_key               ║"
    @echo "╠══════════════════════════════════════════════════════════════╣"
    @echo "║  Connect:                                                    ║"
    @echo "║    ssh -i tests/initramfs/build/client_ssh_key \\             ║"
    @echo "║        -o StrictHostKeyChecking=no -p 2222 root@127.0.0.1    ║"
    @echo "╚══════════════════════════════════════════════════════════════╝"
    @echo ""

# ── Build ──────────────────────────────────────────────────
#
# Build verbs follow a two-level convention:  just build <object> [args]
#   just build                    # default board (NanoPi R3S)
#   just build board <BOARD>      # specific board
#   just build kernel <ARCH>      # kei kernel only (aarch64|x86_64|riscv64)
#   just build vtty <ARCH>        # aris-render kei_tty vtty console (musl cross)
#   just build desktop <ARCH>     # full stack: kernel + vtty + initramfs

# Build dispatcher: just build <object> [args...]
[script('python')]
build WHAT="default" ARG1="":
    import subprocess, sys
    what = "{{WHAT}}"
    arg1 = "{{ARG1}}"
    if what == "default":
        sys.exit(subprocess.run(["just", "_build-default"]).returncode)
    elif what == "board":
        sys.exit(subprocess.run(["just", "_build-board", arg1]).returncode)
    elif what == "kernel":
        sys.exit(subprocess.run(["just", "build-arch", arg1]).returncode)
    elif what == "vtty":
        sys.exit(subprocess.run(["just", "_build-browser", arg1]).returncode)
    elif what == "browser":
        sys.exit(subprocess.run(["just", "_build-browser", arg1]).returncode)
    elif what == "desktop":
        sys.exit(subprocess.run(["just", "_build-desktop", arg1]).returncode)
    else:
        print("Usage: just build [board|kernel|vtty|browser|desktop] [arg]")
        print("  just build              # default board (NanoPi R3S)")
        print("  just build board <name> # specific board")
        print("  just build kernel <arch>  # aarch64|x86_64|riscv64")
        print("  just build vtty <arch>    # aris-render kei_tty console (musl cross)")
        print("  just build desktop <arch> # full stack")
        sys.exit(1)

_build-default:
    just cache-guard
    {{python_cmd}} scripts/build.py nanopi-r3s

_build-board BOARD:
    just cache-guard
    {{python_cmd}} scripts/build.py {{BOARD}}

# ── Dev ─────────────────────────────────────────────────────

# Quick dev launch: build + run QEMU for the host architecture.
# On Windows defaults to aarch64 (SDL window + virtio-gpu display).
# Usage: just dev              # auto-detect (aarch64 on Windows)
#        just dev aarch64      # ARM64 with SDL window
#        just dev x86_64       # x86_64 serial console
dev ARCH="":
    just run {{ARCH}}

# Run kei with the aris-rendered vtty console filling the entire screen
# (Linux-kernel-console-style status screen served by kei_tty).
# Usage: just render             # aarch64 QEMU + aris-rendered vtty
[script('python')]
[unix]
render ARCH="aarch64":
    import os, subprocess, sys
    sys.exit(subprocess.run(["just", "_run-aarch64", "0"],
                            env=dict(os.environ, RENDER_UI="1")).returncode)

[windows]
render ARCH="aarch64":
    $env:RENDER_UI='1'; just _run-aarch64 0

# ── aris cross-compilation (vtty console) ─────────────────
#
# Internal recipes invoked by `just build browser` / `just build desktop`.
# aris must be checked out at $ARIS_REPO (see .env / .env.example).
# The build runs inside WSL because Windows has no musl cross-toolchain;
# aris's .cargo/config.toml uses rust-lld self-contained linking.

# Compile the aris-render vtty console (kei_tty) for the target arch.
# kei is vtty-only during the gateway-mode transition (no GUI): kei_tty
# blits a host-pre-rendered Linux-kernel-console-style frame to /dev/fb0
# and serves the WS JSON-RPC gateway on :8423.
# Invoked via: just build vtty <ARCH>   (alias: just build browser <ARCH>)
[script('python')]
_build-browser ARCH="aarch64":
    import os, pathlib, re, subprocess, sys
    arch = "{{ARCH}}"
    aris = "{{ARIS_REPO}}"
    if arch == "aarch64":
        triple = "aarch64-unknown-linux-musl"
    elif arch == "riscv64":
        triple = "riscv64gc-unknown-linux-musl"
    elif arch == "x86_64":
        triple = "x86_64-unknown-linux-musl"
    else:
        print(f"Unsupported arch: {arch} (aarch64|riscv64|x86_64)")
        sys.exit(1)

    # Resolve ARIS to an absolute path, then convert to a WSL /mnt/... path
    # so cargo inside Ubuntu-24.04 can find the source tree.
    try:
        aris_abs = os.path.abspath(aris)
    except OSError:
        aris_abs = aris
    print(f"[build vtty] ARIS_REPO={aris_abs}  triple={triple}")

    # Windows path → WSL path (D:\foo\bar → /mnt/d/foo/bar)
    wsl_aris = aris_abs.replace("\\", "/")
    wsl_aris = re.sub(r"^([A-Za-z]):", lambda m: "/mnt/" + m.group(1).lower(), wsl_aris)

    r = subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "--", "bash", "-lc",
         'cd "$1" && source ~/.cargo/env 2>/dev/null && RUSTUP_TOOLCHAIN=nightly-2026-05-01 cargo build --release --target "$2" -p aris-render --no-default-features --features png --bin kei_tty',
         "bash", wsl_aris, triple],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = r.stdout.decode("utf-8", errors="replace").splitlines()
    for line in lines[-15:]:
        print(line)

    print(f"[build vtty] done: {aris_abs}/target/{triple}/release/kei_tty")

# Full vtty stack: kernel + kei_tty console + initramfs.
# (kei is vtty-only during the gateway-mode transition — the aris-rendered
# GUI desktop chain is retired.)
# Invoked via: just build desktop <ARCH>
[script('python')]
_build-desktop ARCH="aarch64":
    import os, subprocess, sys
    arch = "{{ARCH}}"
    print(f"═══════ build vtty stack: {arch} ═══════")
    print("[1/3] Building kei kernel...")
    subprocess.run(["just", "build-arch", arch], check=True)
    print("[2/3] Building aris-render kei_tty console...")
    subprocess.run(["just", "_build-browser", arch], check=True)
    print("[3/3] Packaging initramfs...")
    env = dict(os.environ, ARIS_REPO="{{ARIS_REPO}}")
    rc = subprocess.run(
        ["{{python_cmd}}", "scripts/build_render_initramfs.py", "kei_tty"],
        env=env).returncode
    if rc != 0:
        sys.exit(rc)
    print(f"═══════ done: just render {arch} ═══════")

# Build only (no QEMU launch).
dev-build ARCH="":
    just build-arch {{ARCH}}

# Build the kernel for a specific architecture.
# Usage: just build-arch aarch64  (or x86_64, riscv64, loongarch64)
[script('python')]
build-arch ARCH:
    import os, subprocess, sys
    arch = "{{ARCH}}"
    if arch == "aarch64":
        sys.exit(subprocess.run(["just", "_build-aarch64"]).returncode)
    elif arch == "x86_64":
        # x86_64 needs VDSO_LIBRARY_DIR pointing at the prebuilt vDSO .so.
        env = dict(os.environ, VDSO_LIBRARY_DIR="tests/vdso")
        sys.exit(subprocess.run(
            ["cargo", "osdk", "build", "--scheme", "microvm", "--target-arch", "x86_64"],
            env=env).returncode)
    elif arch == "riscv64":
        sys.exit(subprocess.run(
            ["cargo", "osdk", "build", "--scheme", "riscv", "--target-arch", "riscv64"]).returncode)
    elif arch == "loongarch64":
        sys.exit(subprocess.run(
            ["cargo", "osdk", "build", "--scheme", "loongarch", "--target-arch", "loongarch64"]).returncode)
    else:
        print(f"Unsupported arch: {arch}")
        print("Supported: aarch64, x86_64, riscv64, loongarch64")
        sys.exit(1)

# Build aarch64 kernel + ARM64 Image + initramfs (internal).
[script('python')]
_build-aarch64:
    import pathlib, shutil, subprocess, sys
    print("[build] Building aarch64 kernel...")
    KEI = "/mnt/d/源代码/工程项目/celestia/kei"
    r = subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "--", "bash", "-lc",
         'source ~/.cargo/env 2>/dev/null; cd "/mnt/d/源代码/工程项目/celestia/kei" && cargo osdk build --scheme aarch64 --target-arch aarch64'],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = r.stdout.decode("utf-8", errors="replace").splitlines()
    for line in lines[-5:]:
        print(line)
    if r.returncode != 0:
        sys.exit(r.returncode)
    # Copy ELF if OSDK packaging failed (WSL/9p issue)
    elf_src = pathlib.Path("target/osdk/aster-kernel-osdk-bin.qemu_elf")
    elf_dst = pathlib.Path("target/osdk/aster-kernel/aster-kernel-osdk-bin.qemu_elf")
    if not elf_dst.exists() and elf_src.exists():
        shutil.copy(elf_src, elf_dst)
    # Build ARM64 Image from ELF
    print("[build] Creating ARM64 Image...")
    r = subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "--", "bash", "-c",
         'python3 "/mnt/d/源代码/工程项目/celestia/kei/scripts/tools/make_arm64_image.py" "/mnt/d/源代码/工程项目/celestia/kei/target/osdk/aster-kernel/aster-kernel-osdk-bin.qemu_elf" "/mnt/d/源代码/工程项目/celestia/kei/target/osdk/aster-kernel/aster-kernel-osdk-bin.image" 2>&1 | tail -1'],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(r.stdout.decode("utf-8", errors="replace"))
    if r.returncode != 0:
        sys.exit(r.returncode)
    print("[build] Done. Kernel image: target/osdk/aster-kernel/aster-kernel-osdk-bin.image")

# Format Rust + Markdown docs
fmt:
    just fmt-toml
    cargo fmt --all
    just fmt-markdown

fmt-check:
    cargo fmt --all -- --check
    just fmt-markdown --check

check-bsp:
    cd bsp; cargo check

# Build the aarch64 initramfs with dropbear SSH server.
initramfs:
    just setup-keys
    {{python_cmd}} scripts/initramfs.py --arch aarch64

initramfs-force:
    just setup-keys
    {{python_cmd}} scripts/initramfs.py --arch aarch64 --force

# ── Run / Debug ─────────────────────────────────────────────
#
# Launch QEMU for interactive use.
#   - aarch64: SDL window (virtio-gpu) + SSH (dropbear, port 2222)
#   - x86_64 / riscv64 / loongarch64: serial console (cargo osdk run)
#
# Usage:
#   just run              # host arch (auto-detected)
#   just run aarch64      # ARM64 with SDL window + SSH
#   just run x86_64       # x86_64 serial console
#   just run riscv64      # RISC-V serial console
#   just run headless     # aarch64 without GUI (SSH only)

# Launch QEMU. Defaults to host architecture; pass ARCH to override.
[script('python')]
run ARCH="":
    import platform, subprocess, sys
    arg = "{{ARCH}}"
    if not arg:
        # Auto-detect host architecture
        host_arch = platform.machine().lower()
        if host_arch in ("x86_64", "amd64"):
            arg = "x86_64"
        elif host_arch in ("aarch64", "arm64"):
            arg = "aarch64"
        elif host_arch == "riscv64":
            arg = "riscv64"
        elif host_arch == "loongarch64":
            arg = "loongarch64"
        else:
            arg = "x86_64"
        print(f"[run] Auto-detected host arch: {host_arch} → {arg}")

    if arg == "headless":
        arg = "aarch64"
        headless = "1"
    else:
        headless = "0"

    print()
    print("═══════════════════════════════════════════════════════")
    print(f"  kei VM — Architecture: {arg}")
    print("═══════════════════════════════════════════════════════")
    print()

    if arg == "aarch64":
        sys.exit(subprocess.run(["just", "_run-aarch64", headless]).returncode)
    elif arg == "x86_64":
        sys.exit(subprocess.run(["just", "_run-x86_64"]).returncode)
    elif arg == "riscv64":
        sys.exit(subprocess.run(["just", "_run-riscv64"]).returncode)
    elif arg == "loongarch64":
        sys.exit(subprocess.run(["just", "_run-loongarch64"]).returncode)
    else:
        print(f"Unsupported arch: {arg}")
        print("Supported: aarch64, x86_64, riscv64, loongarch64")
        print("  just run aarch64    — ARM64 with SDL window + SSH")
        print("  just run x86_64     — x86_64 with serial console")
        print("  just run riscv64    — RISC-V with serial console")
        print("  just run headless   — aarch64 without GUI")
        sys.exit(1)

# Internal: launch aarch64 QEMU.
[script('python')]
_run-aarch64 HEADLESS:
    import os, pathlib, subprocess, sys, time
    headless = "{{HEADLESS}}"

    # Ensure SSH keys exist
    subprocess.run(["just", "setup-keys"], check=True)

    # Ensure kernel is built
    kernel_image = pathlib.Path("target/osdk/aster-kernel/aster-kernel-osdk-bin.image")
    if not kernel_image.exists():
        print("[run] Kernel image not found, building...")
        subprocess.run(["just", "_build-aarch64"], check=True)

    # Kill any existing QEMU
    subprocess.run(["taskkill", "/F", "/IM", "qemu-system-aarch64.exe"], capture_output=True)
    subprocess.run(["taskkill", "/F", "/IM", "qemu-system-aarch64"], capture_output=True)
    time.sleep(1)

    # Determine display mode
    if headless == "1":
        display_opt = ["-display", "none"]
        print("[run] Headless mode (no GUI window)")
    else:
        display_opt = ["-display", "sdl"]
        print("[run] SDL window mode (GUI terminal)")

    print()

    # Print SSH info BEFORE launching QEMU
    subprocess.run(["just", "ssh-info"], check=True)

    print("  Serial log: target/qemu_serial.log")
    print("  Kernel:     target/osdk/aster-kernel/aster-kernel-osdk-bin.image")
    print()

    # Native Windows paths (no cygpath needed on a Windows host)
    winimage = str(kernel_image.resolve())
    # Use the aris-rendered vtty initramfs if RENDER_UI=1, else the SSH/shell initramfs.
    if os.environ.get("RENDER_UI") == "1":
        initramfs_path = "tests/initramfs/build/initramfs_kei_tty.cpio.gz"
        print("[run] Using aris-rendered vtty (kei_tty) initramfs")
    else:
        initramfs_path = "tests/initramfs/build/initramfs_aarch64.cpio.gz"
    wininitrd = str(pathlib.Path(initramfs_path).resolve())
    winlog = str(pathlib.Path("target/qemu_serial.log").resolve())

    # Launch QEMU in the foreground. The SDL window appears, and the terminal
    # stays attached. Press Ctrl+C or close the window to stop.
    # -monitor tcp: provides a HMP monitor on port 55555 for screendump etc.
    print("[run] Launching QEMU (Ctrl+C or close window to stop)...")
    print("[run] Monitor: tcp://127.0.0.1:55555 (use 'just screenshot' to capture)")
    print()
    qemu = r"C:\Program Files\qemu\qemu-system-aarch64.exe"
    sys.exit(subprocess.run([
        qemu,
        "-cpu", "cortex-a72", "-machine", "virt,gic-version=3,virtualization=on",
        "-m", "2G", "-smp", "1", "--no-reboot",
    ] + display_opt + [
        "-device", "virtio-gpu-device",
        "-device", "virtio-keyboard-device",
        "-serial", "file:" + winlog,
        "-monitor", "tcp:127.0.0.1:55555,server,nowait",
        "-netdev", "user,id=net0,hostfwd=tcp::2222-:22",
        "-device", "virtio-net-device,netdev=net0",
        "-kernel", winimage,
        "-initrd", wininitrd,
        "-append", "init=/init SHELL=/bin/sh LOGNAME=root HOME=/ USER=root PATH=/bin:/sbin",
    ]).returncode)

# Internal: launch x86_64 QEMU via cargo osdk run.
[script('python')]
_run-x86_64:
    import subprocess, sys
    print("[run] x86_64 uses 'cargo osdk run' with serial console")
    print("[run] No SSH server on x86_64 (uses serial shell)")
    print()
    sys.exit(subprocess.run(
        ["cargo", "osdk", "run", "--scheme", "microvm", "--target-arch", "x86_64"]).returncode)

# Internal: launch RISC-V QEMU via cargo osdk run.
[script('python')]
_run-riscv64:
    import subprocess, sys
    print("[run] RISC-V uses 'cargo osdk run' with serial console")
    print("[run] No SSH server on RISC-V (uses serial shell)")
    print()
    sys.exit(subprocess.run(
        ["cargo", "osdk", "run", "--scheme", "riscv", "--target-arch", "riscv64"]).returncode)

# Internal: launch LoongArch QEMU via cargo osdk run.
[script('python')]
_run-loongarch64:
    import subprocess, sys
    print("[run] LoongArch uses 'cargo osdk run' with serial console")
    print("[run] No SSH server on LoongArch (uses serial shell)")
    print()
    sys.exit(subprocess.run(
        ["cargo", "osdk", "run", "--scheme", "loongarch", "--target-arch", "loongarch64"]).returncode)

# ── WSL2 QEMU (headless, screenshot-driven) ────────────────
#
# Run kei in WSL2's qemu-system-aarch64 in headless mode and capture
# the display via QEMU monitor screendump. This is the primary path
# for automated CI and screenshot analysis on Windows hosts, since
# WSL2 QEMU avoids the SDL/GUI overhead and the CJK-path-in-WSL blocker
# is sidestepped via the ~/celestia/kei ASCII symlink.
#
# Recipes use the `wslq-` prefix to avoid colliding with the shared
# `wsl-run` recipe in celestia-devtools.just.
#
# Usage:
#   just wslq-run               # run aarch64 headless (100s)
#   just wslq-run 60            # run for 60 seconds
#   just wslq-ui                # run with legacy aris-render kei_ui initramfs
#   just wslq-screenshot        # convert last screendump to PNG

# Run kei aarch64 in WSL2 QEMU headless. Optional SECS (default 100).
# Uses INITRAMFS env var to select the initramfs (default: kei_tty vtty).
[script('python')]
wslq-run SECS="100":
    import os, subprocess, sys
    env = dict(os.environ,
               INITRAMFS=os.environ.get("INITRAMFS", "tests/initramfs/build/initramfs_kei_tty.cpio.gz"))
    sys.exit(subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "-e", "bash", "-lc",
         'bash ~/celestia/kei/scripts/wsl_qemu_aarch64.sh {{SECS}}'],
        env=env).returncode)

# Run kei with the legacy kei_ui (aris-render runtime UI) initramfs.
[script('python')]
wslq-ui SECS="110":
    import os, subprocess, sys
    env = dict(os.environ, INITRAMFS="tests/initramfs/build/initramfs_kei_ui.cpio.gz")
    sys.exit(subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "-e", "bash", "-lc",
         'bash ~/celestia/kei/scripts/wsl_qemu_aarch64.sh {{SECS}}'],
        env=env).returncode)

# Build a render initramfs (kei_tty vtty console by default).
[script('python')]
wslq-initramfs BIN="kei_tty":
    import subprocess, sys
    sys.exit(subprocess.run(
        ["{{python_cmd}}", "scripts/build_render_initramfs.py", "{{BIN}}"]).returncode)

# Convert the last WSL2 screendump to PNG and show pixel stats.
[script('python')]
wslq-screenshot:
    import pathlib, subprocess, sys
    subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "-e", "bash", "-lc",
         'cd ~/celestia/kei && python3 scripts/ppm_to_png.py target/wsl_screendump.ppm target/wsl_screendump.png'],
        check=True)
    p = pathlib.Path("target/wsl_screendump.png")
    if p.exists():
        print(f"total {p.stat().st_size} {p}")
    else:
        print("[wslq-screenshot] no screendump yet")

# Ensure the ~/celestia/kei ASCII symlink exists (bypasses CJK-path blocker).
[script('python')]
wslq-setup:
    import subprocess, sys
    sys.exit(subprocess.run(
        ["wsl", "-d", "Ubuntu-24.04", "-e", "bash", "-lc",
         'mkdir -p ~/celestia && ln -sfn "/mnt/d/源代码/工程项目/celestia/kei" ~/celestia/kei && echo "symlink OK: ~/celestia/kei"']).returncode)

# ── Screenshot ──────────────────────────────────────────────
#
# Capture the QEMU display to a PNG file via the QEMU monitor's
# 'screendump' command. Requires QEMU to be running with
# -monitor tcp:127.0.0.1:55555 (added automatically by 'just run').

# Capture a screenshot of the running QEMU display.
# Usage: just screenshot [filename]
[script('python')]
screenshot FILE="target/screenshot.ppm":
    import os, pathlib, shutil, socket, subprocess, sys
    out = "{{FILE}}"
    # Ensure .ppm extension for QEMU compatibility
    if not out.endswith(".ppm"):
        out = out + ".ppm"
    wout = str(pathlib.Path(out).resolve())

    print(f"[screenshot] Capturing QEMU display to {out} ...")

    # Send 'screendump' to QEMU monitor via TCP
    # The monitor expects commands terminated by newline.
    qemu = r"C:\Program Files\qemu\qemu-system-aarch64.exe"
    if shutil.which("qemu-system-aarch64"):
        qemu = "qemu-system-aarch64"
    try:
        subprocess.run(
            ["cmd", "/c", "echo screendump " + wout + "|", qemu, "-qmp", "stdout"],
            capture_output=True)
    except OSError:
        pass

    # Alternative: use a simple TCP connection to the QEMU monitor
    if not pathlib.Path(out).exists():
        print("[screenshot] /dev/tcp method...")
        try:
            with socket.create_connection(("127.0.0.1", 55555), timeout=5) as s:
                s.settimeout(2)
                try:
                    s.recv(4096)  # Read banner
                except OSError:
                    pass
                # Send screendump
                s.sendall(f"screendump {wout}\n".encode())
                s.settimeout(5)
                try:
                    s.recv(4096)  # Read response
                except OSError:
                    pass
        except OSError:
            print("[screenshot] ERROR: Cannot connect to QEMU monitor on port 55555")
            print("[screenshot] Make sure 'just run' is running.")
            sys.exit(1)

    if pathlib.Path(out).exists():
        size = pathlib.Path(out).stat().st_size
        print(f"[screenshot] Saved {out} ({size} bytes)")

        # Try converting PPM to PNG if ImageMagick is available
        if shutil.which("convert"):
            png = out[:-4] + ".png"
            r = subprocess.run(["convert", out, png], capture_output=True)
            if r.returncode == 0:
                print(f"[screenshot] Converted to {png}")
                os.remove(out)
        elif shutil.which("python3") or shutil.which("python"):
            png = out[:-4] + ".png"
            py = shutil.which("python3") or shutil.which("python")
            r = subprocess.run([py, "scripts/ppm_info.py", out], capture_output=True)
            if r.returncode == 0:
                print("[screenshot] PPM validated")
    else:
        print("[screenshot] ERROR: Screenshot file not created.")
        print("[screenshot] The QEMU monitor screendump may not support the path.")
        print("[screenshot] Try: just screenshot target/screenshot")

# Connect to the running aarch64 VM via SSH.
ssh:
    @echo "Connecting to kei VM via SSH..."
    ssh -i tests/initramfs/build/client_ssh_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@127.0.0.1

# Stop the running QEMU instance.
[script('python')]
kill:
    import subprocess
    for image in ("qemu-system-aarch64.exe", "qemu-system-x86_64.exe", "qemu-system-riscv64.exe"):
        subprocess.run(["taskkill", "/F", "/IM", image], capture_output=True)
    subprocess.run(["taskkill", "/F", "/IM", "qemu-system-aarch64"], capture_output=True)
    subprocess.run(["taskkill", "/F", "/IM", "qemu-system-x86_64"], capture_output=True)
    subprocess.run(["taskkill", "/F", "/IM", "qemu-system-riscv64"], capture_output=True)
    print("QEMU stopped.")

# Show the serial log (boot messages).
[script('python')]
log:
    import pathlib, sys
    p = pathlib.Path("target/qemu_serial.log")
    if p.exists():
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines()[-50:]:
            print(line)
    else:
        print("No serial log found. Run 'just run' first.")

# Watch the serial log in real-time.
[script('python')]
log-follow:
    import pathlib, sys, time
    p = pathlib.Path("target/qemu_serial.log")
    if not p.exists():
        print("No serial log found.")
        sys.exit(0)
    with p.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            print(line, end="")
        sys.stdout.flush()
        while True:
            line = f.readline()
            if line:
                print(line, end="")
                sys.stdout.flush()
            else:
                time.sleep(0.5)

# ── Test ───────────────────────────────────────────────────

test-all:
    {{python_cmd}} scripts/test_all_arch.py

test-arch ARCH:
    {{python_cmd}} scripts/test_all_arch.py {{ARCH}}

test BOARD="nanopi-r3s":
    {{python_cmd}} scripts/test.py {{BOARD}}

test-bsp:
    cargo test -p bsp-rk3566 -p bsp-bcm2711 -p bsp-jh7110

# ── Utilities ──────────────────────────────────────────────

list-boards:
    ls configs/*.toml | grep -v default | xargs -I{} basename {} .toml

# List all supported architectures and their run commands.
list-arch:
    @echo ""
    @echo "kei supported architectures:"
    @echo ""
    @echo "  Host arch (auto-detected by 'just run')"
    @echo "               just run              — auto: x86_64 on PC, aarch64 on ARM"
    @echo ""
    @echo "  aarch64      ARM64 (QEMU virt) — SDL window + SSH (port 2222)"
    @echo "               just run aarch64"
    @echo "               just run headless   (no GUI, SSH only)"
    @echo "               just ssh            (connect)"
    @echo ""
    @echo "  x86_64       x86-64 (QEMU pc) — serial console"
    @echo "               just run x86_64"
    @echo ""
    @echo "  riscv64      RISC-V (QEMU virt) — serial console"
    @echo "               just run riscv64"
    @echo ""
    @echo "  loongarch64  LoongArch (QEMU virt) — serial console"
    @echo "               just run loongarch64"
    @echo ""
    @echo "Other commands:"
    @echo "  just setup-keys    Generate SSH keys (one-time)"
    @echo "  just ssh-info      Show SSH connection details"
    @echo "  just kill          Stop QEMU"
    @echo "  just log           Show boot log"
    @echo "  just log-follow    Follow boot log live"
    @echo ""

# ── SD Card Image (Real Hardware) ──────────────────────────
#
# Build a bootable SD card image for the target board.
# Requires an Armbian reference image for U-Boot.
#
# Usage:
#   just image ARMBIAN_IMG=/path/to/armbian.img
#
# Example:
#   just image ARMBIAN_IMG=Armbian_26.5.1_Nanopi-r3s-lts_trixie_current_6.18.33_minimal.img

[script('python')]
image ARMBIAN_IMG="" BOARD="nanopi-r3s":
    import subprocess, sys
    if not "{{ARMBIAN_IMG}}":
        print("Usage: just image ARMBIAN_IMG=/path/to/armbian.img [BOARD=nanopi-r3s]")
        print("")
        print("The Armbian image provides U-Boot (sector 64-32767) required for")
        print("Rockchip BootROM to start the device. The resulting sdcard.img")
        print("contains kei kernel + DTB + initramfs in a single boot partition.")
        print("")
        print("Download: https://www.armbian.com/nanopi-r3s/")
        sys.exit(1)
    r = subprocess.run(["just", "build", "board", "{{BOARD}}"])
    if r.returncode != 0:
        sys.exit(r.returncode)
    sys.exit(subprocess.run(
        ["{{python_cmd}}", "scripts/make_sdcard.py", "{{BOARD}}",
         "--armbian-image", "{{ARMBIAN_IMG}}"]).returncode)

# Build everything and create the SD card image (one-shot).
# just image-all ARMBIAN_IMG=/path/to/armbian.img

image-all ARMBIAN_IMG="" BOARD="nanopi-r3s":
    @just image ARMBIAN_IMG="{{ARMBIAN_IMG}}" BOARD="{{BOARD}}"

clean:
    {{python_cmd}} -c "import os, pathlib, shutil; [shutil.rmtree(d, ignore_errors=True) for d in ('build', 'output')]; [os.remove(str(p)) for p in (pathlib.Path('target/qemu_serial.log'), pathlib.Path('target/qemu.pid'), pathlib.Path('target/client_ssh_key')) if p.exists()]"
    cargo clean

dev-shell:
    {{python_cmd}} scripts/dev_shell.py
