# kei — Asterinas ARM64 Fork

[![License](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE-MPL)

Independent fork of [asterinas/asterinas](https://github.com/asterinas/asterinas)
with ARM64 support and Board Support Packages for industrial IoT gateways.

## Model: Independent Fork (Apple LLVM Style)

kei is **not** a branch that tracks upstream. It is an **independent fork**
that periodically absorbs upstream changes on its own schedule.

```
asterinas/asterinas          kei (this repo)
(活跃上游)                    (完全独立)
     │                            │
     │  ┌── 每 N 个月 ──────▶     │  vendor-upstream.sh
     │  │   squash 替换            │  (整体吸收，不做 commit 级 merge)
     │  └──────────────────────   │
     │                            │
wanywhn/asterinas                │
(arm64-support)                  │
     │  ┌── 一次性拉取 ──────▶    │  pull-arm64.sh
     │  │   之后独立维护           │  (点快照，之后自己改)
     │  └──────────────────────   │
                                  │
                          ostd/src/arch/aarch64/  ← 我们独立维护
                          kernel/src/arch/aarch64/ ← 我们独立维护
                          bsp/                    ← 100% 我们的代码
                          board/ configs/         ← 100% 我们的代码
```

**为什么不跟踪上游？**
- asterinas 太活跃（4194 commits, SOSP/USENIX 论文），频繁 merge 冲突成本 > 收益
- 上游 lrh2000 会重写 arm64，不会用我们的版本，追求 upstream 兼容无意义
- 初创团队资源有限，按自己节奏吸收上游更务实
- 这正是 Apple 维护 LLVM fork 的方式

## Relationship to aris

```
kei (this repo)                    aris (gateway firmware)
├── ostd/  ← vendored periodically    ├── packages/core/    ← supervisor
├── kernel/← vendored periodically    ├── packages/builder/ ← image builder
├── bsp/   ← 100% our code            ├── overlay/          ← rootfs files
└── board/ ← 100% our code            └── scripts/          ← build + flash
       │                                      │
       └── kei-kernel.bin ───────────────────┘
```

## Quick Start

```bash
just setup        # Configure git remotes
just vendor       # Absorb latest upstream asterinas (squash)
just pull-arm64   # Pull ARM64 code from wanywhn fork (one-time)
just versions     # Show what upstream versions we're based on
just build        # Build kernel for nanopi-r3s (aarch64)
just test-all     # Boot-test all architectures in QEMU
```

## What Lives Where

| Directory | Origin | Maintenance |
|-----------|--------|-------------|
| `ostd/` | Upstream asterinas | Vendored periodically, bugs fixed in-place |
| `ostd/src/arch/aarch64/` | wanywhn fork (PR #3270) | **Independent** — we own this |
| `kernel/` | Upstream asterinas | Vendored periodically |
| `kernel/src/arch/aarch64/` | wanywhn fork (PR #3270) | **Independent** — we own this |
| `osdk/` | Upstream asterinas | Vendored periodically |
| `bsp/` | kei | **100% ours** — Board Support Packages |
| `board/` `configs/` | kei | **100% ours** — board definitions |
| `scripts/` `docs/` | kei | **100% ours** — tooling and docs |

## Supported Architectures

| Arch | Status | QEMU Test |
|------|--------|-----------|
| x86_64 | Upstream Tier 1 | ✅ q35 |
| aarch64 | kei-maintained (from PR #3270) | ✅ virt/cortex-a55 |
| riscv64 | Upstream Tier 2 | ⚠️ virt/rv64 |
| loongarch64 | Upstream Tier 3 | ⚠️ virt/max |

## License

MPL-2.0 (same as upstream Asterinas)
