# kei — 项目状态与计划 (PLAN)

> 本文件由自动化扫描于 **2026-07-04** 生成，记录项目当前状态、近期进展与后续计划。
> 原有详细计划已保留于文末「既有详细计划（存档）」。

## 1. 项目概述

- **名称**：`kei`
- **简介**：Asterinas ARM64 fork —— 面向工业物联网网关的独立内核。
- **远程仓库**：本地仓库（无 origin）
- **技术栈**：Rust / just
- **类别**：firmware

## 2. 当前状态

- **当前分支**：`dev`
- **工作区**：干净
- **最近提交时间**：2026-07-04
- **最近提交**：docs: rewrite License section in flowing paragraph style (all 8 languages)

## 3. 未提交改动

无。

## 4. 近期进展（最近提交）

- docs: rewrite License section in flowing paragraph style (all 8 languages)
- docs: rewrite License section in entelecheia flowing paragraph style
- docs: standardize License section format across all translations
- style: use uppercase ARIS / KEI throughout
- chore: stop tracking Cargo.lock (again)
- docs: use GitHub raw URL for logo, bold English without self-link

## 5. 后续计划

1. 推进板级/驱动或协议落地里程碑，保持跨设备回归测试。
2. 收敛审计遗留项，固化启动与健康检查流程。
3. 定期刷新本 PLAN.md 以反映最新状态。

---

## 既有详细计划（存档）

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
- [x] First successful vendor + arm64 pull + aarch64 boot

> **Status**: Kernel boots in QEMU aarch64 (cortex-a72, virt, GICv3).
> Reaches OSTD `frame::meta::init` before crashing on FDT memory region
> parsing (region 6 has an overflowing physical address range).
> Build pipeline produces a valid ARM64 Image (.bin) with correct header.

### M2 — ARM64 Hardening
The wanywhn arm64 code is LLM-generated and QEMU-only. Hardening tasks:
- [ ] Fix FDT memory region parsing (region 6 overflows PA space)
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

