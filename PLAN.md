# kei — 项目状态与计划 (PLAN)

> 本文件于 **2026-07-04** 更新，记录项目当前状态、近期进展与后续计划。
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
- **最近提交**：test: add kei+evernight E2E QEMU ignition test script
- **initramfs**：已构建（`test/initramfs/build/initramfs.cpio.gz`，aarch64 busybox + init）

## 3. 未提交改动

无。

## 4. 近期进展

### kei 内核完整启动 + 用户空间进程（2026-07-04）🎉

**重大里程碑**：kei 内核在 QEMU arm64 上完整启动并成功加载用户空间 ELF 进程。

通过 Docker QEMU 镜像（`qemu-system-aarch64`）在 QEMU virt（cortex-a72, GICv3, 2GB）上验证：

```
[kei] FDT parsed → DEVICE_TREE initialized
[ostd] frame::meta::init: max_paddr=0xC0000000 (正确的 3GB)
[ostd] init: DONE — GIC, timer, SMP, page tables, IRQ 全部通过
[kernel] 组件初始化: arch, thread, driver, net, sched, process, fs, security
[kernel] initramfs.cpio.gz 解包 → rootfs ready
[kernel] spawn_init_process: 用户空间 ELF 加载成功（init=/init）
```

**修复的问题**：
1. **FDT 内存区域溢出**：链接脚本 `KERNEL_VMA` 与 `kernel_loaded_offset()` 不匹配。重装 cargo-osdk 后链接脚本使用正确的 `0xffff800040080000`（线性映射基址），全量重编译后修复。`max_paddr` 从 `0x7fff40080000`（128TB）降至正确的 `0xC0000000`（3GB）。
2. **vbe_dispi x86 模块**：`kernel/src/lib.rs` 中 `mod vbe_dispi` 未门控，添加 `#[cfg(target_arch = "x86_64")]`。
3. **initramfs 架构错误**：`initramfs.py` 使用宿主机 x86-64 busybox。添加 `find_busybox(arch)` 函数，支持按架构选择 busybox。

### evernight 联调（2026-07-04）

与 aris + evernight 进行宿主机联调测试，验证 IoT 网关数据链路：

```
Modbus TCP sim → evernight sensor-poll → WebSocket → evernight-server
```

- evernight 二进制构建成功，device.register + device.telemetry 双向验证通过
- aris `ignition_test.py` 修复：`SENSOR_DATA_DIR` 注入 + Modbus TCP sim 帧解析

### kei + evernight E2E QEMU 点火测试（2026-07-04）
- `tests/e2e_qemu_ignition.sh`（177 行）：QEMU arm64 中 kei 内核启动 → evernight sensor-poll → gateway 全链路测试脚本
- evernight-server 作为 mock entelecheia gateway（8443 端口）
- QEMU user-mode NAT 网络（guest 10.0.2.15 ↔ host 10.0.2.2）

### 既往提交

- fix: gate vbe_dispi module to x86_64 only (aarch64 build fix)
- feat: fix build/test pipeline + verify aarch64 QEMU boot
- milestone: kei Asterinas kernel FULLY BOOTS on aarch64 QEMU

## 5. 后续计划

### 短期
1. **用户空间串口输出**——init 进程已加载但 stdout 未连接到串口（console/stdio setup 问题）
2. **busybox ELF TLS 加载**——busybox 的 TLS 段触发 `copy_from_slice::len_mismatch_fail`（FileSiz=0x40 vs 分配 buffer），需修复 ELF 加载器 TLS 处理
3. **evernight aarch64 交叉编译**——构建 `aarch64-unknown-linux-musl` evernight 二进制，在 kei QEMU 中运行
4. **kei + evernight 联调**——QEMU 中 kei 内核启动 → evernight 连接 gateway

### 中期
1. M2 ARM64 Hardening：审计 ostd/src/arch/aarch64/，替换第三方 GICv3 crate
2. M2 SMP/PSCI 多核启动
3. M3 RK3566 BSP 驱动（GPIO / stmmac / DW UART）

### 长期
1. M2.4 在 NanoPi R3S 上运行 kei + evernight 全栈
2. 性能基准测试 vs Linux baseline

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

> **Status** (2026-07-04): Kernel FULLY BOOTS on QEMU aarch64 (cortex-a72, virt, GICv3).
> All OSTD subsystems initialize successfully. Kernel components (arch, thread,
> driver, net, sched, process, fs, security) all pass. Initramfs unpacked to
> rootfs. User-space ELF process successfully loaded and spawned (init=/init).
> max_paddr = 0xC0000000 (correct 3GB for 2GB RAM + MMIO).
> Previous FDT region 6 overflow bug RESOLVED via linker script fix + clean rebuild.

### M2 — ARM64 Hardening
The wanywhn arm64 code is LLM-generated and QEMU-only. Hardening tasks:
- [x] Fix FDT memory region parsing (region 6 overflows PA space) ← **RESOLVED 2026-07-04**
- [ ] Audit all files in ostd/src/arch/aarch64/, fix LLM artifacts
- [ ] Replace third-party GICv3 crate with in-tree driver
- [ ] SMP / multi-core boot (PSCI secondary bring-up)
- [ ] Real hardware boot on NanoPi R3S (RK3566)
- [ ] Performance benchmarks vs Linux baseline
- [x] QEMU arm64 boot reaches user-space init ← **DONE 2026-07-04**
- [ ] Fix busybox TLS ELF loading (copy_from_slice panic)
- [ ] Connect user-space stdout to serial console

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

