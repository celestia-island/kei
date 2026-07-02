# kei — Asterinas ARM64 Distribution

[![License](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

Asterinas kernel distribution for ARM64 embedded devices. Applies the
[PR #3270](https://github.com/asterinas/asterinas/pull/3270) ARM64 support
patches on top of upstream [asterinas/asterinas](https://github.com/asterinas/asterinas)
and adds Board Support Packages (BSP) for industrial IoT gateways.

## Relationship to aris

```
kei (kernel)  ──builds──▶  Kernel binary + DTB
                              │
aris (firmware)  ◀───────────┘
  └─ Rootfs + Supervisor + evernight → Bootable SD image
```

## Architecture

```
asterinas/asterinas (upstream, MPL-2.0)
  │
  ├── wanywhn/asterinas arm64-support branch (PR #3270)
  │     └── patches/arm64/  ← extracted ARM64 diffs
  │
  └── kei (this repo)
        ├── bsp/            ← Board Support Packages (our additions)
        ├── board/          ← Board definitions & device trees
        ├── scripts/        ← Fetch, patch, build, test
        └── configs/        ← Per-board build configuration
```

## Quick Start

```bash
just setup      # Fetch asterinas upstream + apply ARM64 patches
just build      # Build kernel for default target (nanopi-r3s)
just test       # Boot in QEMU arm64 virt machine
```

## Supported Targets

| Board | SoC | Arch | Status |
|-------|-----|------|--------|
| NanoPi R3S | RK3566 | aarch64 | Active |
| Raspberry Pi 4 | BCM2711 | aarch64 | Planned |
| VisionFive 2 | JH7110 | riscv64 | Planned |

## License

MPL-2.0 (same as upstream Asterinas)
