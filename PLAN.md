# kei — Project Plan

## Goal

Maintain a production-ready Asterinas kernel fork for ARM64 and other
embedded architectures, with comprehensive Board Support Packages and
multi-architecture QEMU testing.

## Design: Why a Fork (Not Patches)

### The Problem with Patches

The ARM64 architecture port is **4,475 lines across 80 files** — comparable
to an entire new `ostd/src/arch/aarch64/` directory tree. Managing this as
a quilt patch series is fragile:

- Rebase conflicts on every upstream sync
- No IDE support for "files that only exist in patches"
- Can't test changes without applying patches first
- The "gradually disappear" narrative is confusing

### The Fork Model

kei is a **git fork** that merges from two upstreams:

```
                   asterinas/asterinas (main)
                          │
                    git merge upstream/main
                          │
                          ▼
    wanywhn/asterinas ──▶ kei (dev)
    (arm64-support)        │  = upstream + arm64 + BSP + configs
         │                 │
    git merge arm64        │
```

**Sync workflow** (`scripts/sync-upstream.sh`):
1. `git fetch upstream main`
2. `git merge upstream/main` (prefer kei changes on conflict)
3. `git fetch arm64 arm64-support`
4. `git merge arm64/arm64-support` (prefer arm64 changes on conflict)
5. Run `just test-all` to verify nothing broke

**Lifecycle**: As ARM64 merges into official asterinas, the `arm64` remote
becomes redundant. kei drops it and the delta shrinks to just BSP + configs.
Eventually BSP drivers upstream too, and kei becomes a thin board-config layer.

This is the same evolution path as Armbian: start as a fork carrying vendor
patches, gradually upstream everything, end up as a config-only layer.

## Architecture

### Source Composition

kei's tree contains three categories of code:

| Category | Directory | Origin | Modifiable |
|----------|-----------|--------|------------|
| Framework | `ostd/` | asterinas upstream | Bug fixes only |
| Framework (arm64) | `ostd/src/arch/aarch64/` | wanywhn fork | Active development |
| Kernel | `kernel/` | asterinas upstream | Bug fixes only |
| Kernel (arm64) | `kernel/src/arch/aarch64/` | wanywhn fork | Active development |
| Build tool | `osdk/` | asterinas upstream | Minimal changes |
| **BSP** | `bsp/` | **kei** | **Primary development** |
| **Board configs** | `board/`, `configs/` | **kei** | **Primary development** |
| **Build/test scripts** | `scripts/` | **kei** | **Primary development** |

### Testing Strategy

Following the Linux kernel / KernelCI model:

| Test Level | What | How |
|-----------|------|-----|
| Per-architecture boot | Kernel boots to console | QEMU per arch (`test-all-arch.sh`) |
| BSP unit tests | Driver logic | `cargo osdk test` (ktest) |
| Integration | evernight talks to devices | QEMU + virtio-net, aris integration |
| Hardware | Real board boot | NanoPi R3S + sensors |

Architectures tested by `test-all-arch.sh`:
- `x86_64` — QEMU q35 (upstream baseline)
- `aarch64` — QEMU virt / cortex-a55 (our primary target)
- `riscv64` — QEMU virt / rv64 (future)
- `loongarch64` — QEMU virt / max (future)

## Milestones

### M1 — Fork Bootstrap
- [x] Repository structure aligned with asterinas conventions
- [x] Git merge workflow (`sync-upstream.sh`)
- [x] Multi-architecture QEMU test harness (`test-all-arch.sh`)
- [ ] First successful merge of upstream + arm64
- [ ] QEMU aarch64 boot test passes

### M2 — ARM64 Stabilization
The wanywhn arm64-support branch is LLM-generated and QEMU-only.
We need to harden it:
- [ ] Audit all 80 changed files, fix LLM artifacts
- [ ] Replace third-party GICv3 crate with in-tree driver
- [ ] Add SMP / multi-core boot support (PSCI)
- [ ] Real hardware boot on NanoPi R3S (RK3566)
- [ ] Performance benchmarks vs Linux baseline

### M3 — RK3566 BSP
Board-specific drivers, built as OSDK library crates:
- [ ] GPIO (Rockchip GRF pinctrl)
- [ ] Dual Ethernet (stmmac / RK GMAC)
- [ ] UART (DW 8250)
- [ ] SPI (DW SSI)
- [ ] I2C (RK3x)
- [ ] Watchdog (DW WDT)
- [ ] SD/eMMC (DW MMC)

### M4 — Multi-Arch Expansion
- [ ] RISC-V: JH7110 BSP (VisionFive 2)
- [ ] ARMv7 evaluation (if upstream adds support)
- [ ] x86_64: Intel N100 BSP (industrial PC)

### M5 — Upstream Convergence
- [ ] ARM64 merged into official asterinas
- [ ] kei drops arm64 remote, tracks upstream only
- [ ] BSP drivers upstreamed where possible
- [ ] kei becomes thin config layer

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| wanywhn branch abandoned | Medium | High | We maintain our own merge; can rebase manually |
| Upstream lrh2000 rewrites arm64 differently | High | Medium | Our BSP layer is arch-agnostic; only `ostd/src/arch/` needs updating |
| LLM-generated code has subtle bugs | High | High | M2 audit milestone; real hardware testing |
| Upstream API breaks arm64 | Medium | Medium | Sync regularly; pin to specific upstream commits |
