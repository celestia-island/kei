# kei — Project Plan

## Goal

Maintain a production-ready Asterinas kernel fork for ARM64 embedded devices,
with comprehensive Board Support Packages and multi-architecture QEMU testing.

## Design: Independent Fork (Apple LLVM Model)

### Why Not Track Upstream?

| Approach | Pro | Con | Verdict |
|----------|-----|-----|---------|
| Regular merge tracking | Catch upstream API breaks early | Constant merge conflicts; resource-heavy | ❌ Too expensive for startup |
| Patch series (quilt) | Clean delta tracking | Fragile for 4475-line arch port; no IDE support | ❌ Wrong tool for scale |
| **Independent fork + squash vendor** | Full control; absorb upstream on our schedule | Must manually detect API breaks at vendor time | ✅ Best fit |

### How Vendoring Works

`scripts/vendor-upstream.sh` does **directory-level replacement**, not git merge:

```
1. Snapshot our code (ostd/src/arch/aarch64/, bsp/, board/, configs/, ...)
2. Delete ostd/, kernel/, osdk/ from kei tree
3. Check out fresh copies from upstream/main
4. Restore our snapshot on top
5. Fix any API breaks (compile errors from changed upstream APIs)
6. Commit as single "vendor: absorb asterinas <sha>"
```

This is exactly how Apple absorbs LLVM upstream: take the whole thing,
overlay Apple-specific changes, commit as one squashed point.

### What We Track vs. What We Own

```
kei tree:
│
├── ostd/                          ← VENDORED (replaced wholesale on upgrade)
│   └── src/arch/
│       ├── x86/                   ← comes with vendoring
│       ├── riscv/                 ← comes with vendoring
│       ├── loongarch/             ← comes with vendoring
│       └── aarch64/               ← OURS (preserved across vendoring)
│
├── kernel/                        ← VENDORED
│   └── src/arch/
│       └── aarch64/               ← OURS (preserved across vendoring)
│
├── osdk/                          ← VENDORED
├── bsp/                           ← OURS (never touched by vendoring)
├── board/ configs/                ← OURS
├── scripts/ docs/                 ← OURS
└── .vendored-upstream             ← tracks which upstream commit we're on
```

### Vendoring Frequency

- **Upstream asterinas**: Every 3-6 months, or when a critical fix lands
- **ARM64 code (wanywhn)**: One-time pull, then independent maintenance.
  Re-pull only if wanywhn makes significant improvements worth absorbing.

## Milestones

### M1 — Fork Bootstrap
- [x] Independent fork structure
- [x] Vendor script (squash/directory-replace model)
- [x] ARM64 pull script (point-in-time snapshot from wanywhn)
- [x] Multi-architecture QEMU test harness
- [ ] First successful vendor + arm64 pull + aarch64 boot

### M2 — ARM64 Hardening
The wanywhn arm64 code is LLM-generated and QEMU-only. Hardening tasks:
- [ ] Audit all files in ostd/src/arch/aarch64/, fix LLM artifacts
- [ ] Replace third-party GICv3 crate with in-tree driver
- [ ] SMP / multi-core boot (PSCI secondary bring-up)
- [ ] Real hardware boot on NanoPi R3S (RK3566)
- [ ] Performance benchmarks vs Linux baseline

### M3 — RK3566 BSP
- [ ] GPIO (Rockchip GRF pinctrl)
- [ ] Dual Ethernet (stmmac / RK GMAC)
- [ ] UART (DW 8250)
- [ ] SPI / I2C / Watchdog
- [ ] SD/eMMC (DW MMC)

### M4 — Multi-Arch Expansion
- [ ] RISC-V: JH7110 BSP (VisionFive 2)
- [ ] ARMv7 evaluation
- [ ] x86_64: Intel N100 BSP

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Upstream API breaks at vendor time | Medium | Vendor script + compile test + fix cycle |
| wanywhn arm64 code has subtle bugs | High | M2 audit milestone; real HW testing |
| Falling behind upstream features | Low | Periodic vendoring catches up in batches |
| Upstream ships different arm64 | Low | Evaluate at vendor time; adopt if better |
