# kei — Asterinas ARM64 Distribution

[![License](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE-MPL)

Downstream fork of [asterinas/asterinas](https://github.com/asterinas/asterinas)
that adds ARM64 architecture support and Board Support Packages (BSP) for
industrial IoT gateways.

## What kei IS

kei is a **downstream fork** that carries modifications on top of upstream
Asterinas. It tracks two upstream sources via git merge:

```
asterinas/asterinas:main        ← base kernel (ostd + kernel + osdk)
wanywhn/asterinas:arm64-support ← ARM64 architecture port (PR #3270)
        │
        ▼
    kei:dev = merge(upstream, arm64) + BSP + board configs + testing
```

## What kei IS NOT

- **Not a patch series** — no quilt, no fragile diffs. ARM64 code lives in the
  tree directly, same as upstream `x86/`, `riscv/`, `loongarch/` directories.
- **Not a permanent fork** — as ARM64 support merges upstream, kei's delta
  shrinks. Eventually kei becomes just BSP configs + board device trees.
- **Not a kernel for end users** — kei produces kernel binaries that
  [aris](https://github.com/celestia-island/aris) packages into bootable firmware.

## Relationship to aris

```
kei (this repo)                    aris (gateway firmware)
├── ostd/         ← from upstream    ├── packages/core/   ← supervisor
├── kernel/       ← from upstream    ├── packages/builder/ ← image builder
├── osdk/         ← from upstream    ├── overlay/         ← rootfs files
├── bsp/rk3566/   ← OUR additions    └── scripts/         ← build + flash
├── board/        ← OUR additions           │
└── scripts/      ← OUR additions           │
       │                                    │
       └── kei-kernel.bin ──────────────────┘  fed into aris image builder
```

## Quick Start

```bash
just setup       # Configure remotes, fetch upstreams
just sync        # Merge latest upstream + arm64-support
just build       # Build kernel for nanopi-r3s (aarch64)
just test-all    # Boot-test all architectures in QEMU
```

## Supported Architectures

| Architecture | Source | QEMU Test | Status |
|-------------|--------|-----------|--------|
| x86_64 | Upstream Tier 1 | q35 / qemu64 | ✅ Works |
| aarch64 | wanywhn arm64-support (PR #3270) | virt / cortex-a55 | ✅ Boots in QEMU |
| riscv64 | Upstream Tier 2 | virt / rv64 | ⚠️ Upstream WIP |
| loongarch64 | Upstream Tier 3 | virt / max | ⚠️ Experimental |

## Supported Boards

| Board | SoC | Arch | BSP Status |
|-------|-----|------|------------|
| NanoPi R3S | RK3566 | aarch64 | Drivers stubbed |
| OrangePi 3B | RK3566 | aarch64 | Planned |
| Raspberry Pi 4 | BCM2711 | aarch64 | Planned |
| VisionFive 2 | JH7110 | riscv64 | Planned |

## Adding a New Architecture

1. Fork or branch from upstream asterinas with the new arch
2. Add `ostd/src/arch/<arch>/` following the x86/riscv pattern
3. Add `kernel/src/arch/<arch>/` for kernel-level arch code
4. Add QEMU scheme in `OSDK.toml`
5. Add the target triple to `rust-toolchain.toml`
6. Run `just test-all` to verify boot on QEMU

## License

MPL-2.0 (same as upstream Asterinas)
