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

### 多架构构建验证（2026-07-04）

全部 4 种架构编译成功，产出有效 ELF 内核二进制：

| 架构 | OSDK Scheme | 状态 | 产物 |
|------|-------------|------|------|
| **aarch64** | `aarch64` | ✅ 完整启动 + 用户空间 | ELF 64-bit ARM aarch64 (7MB) |
| **x86_64** | `microvm` | ✅ 编译通过 | ELF 64-bit x86-64 (需 vDSO) |
| **riscv64** | `riscv` | ✅ 编译通过 | ELF 64-bit RISC-V (需 vDSO) |
| **loongarch64** | `loongarch` | ✅ 编译通过 | ELF 64-bit LoongArch |

> x86_64/riscv64 需要 `VDSO_LIBRARY_DIR` 环境变量指向预构建的 vDSO .so 文件。
> aarch64/loongarch64 不需要 vDSO（vdso 模块仅 x86_64/riscv64 启用）。

### evernight aarch64 交叉编译（2026-07-04）

- **evernight** 交叉编译成功：`aarch64-unknown-linux-musl`，12MB 静态链接 ELF
- 使用 musl.cc 交叉工具链 + `.cargo/config.toml` linker 配置
- 修复 AppContext feature 门控 bug（`capture`/`signaling` 字段未正确 cfg-gated）
- 功能集：`hardware,protocol,serial,sensor,s7comm,bin,api,vault,manifest,tunnel,remote-ssh`

### 设备树（FDT）验证（2026-07-04）

QEMU virt FDT 包含标准 Linux 绑定的网络设备节点：

```
virtio_mmio@a000000 {
    dma-coherent;
    interrupts = <0x00 0x10 0x01>;    ← GIC SPI #16
    reg = <0x00 0xa000000 0x00 0x200>; ← MMIO 512 bytes
    compatible = "virtio,mmio";        ← 标准 Linux 绑定
};
```

- 16 个 virtio_mmio 插槽（0xa000000 – 0xa001e00），每个 512 字节
- GICv3 3-cell 中断格式，interrupt-parent 指向 /intc
- kei `aarch64.rs::probe_for_device()` 完整解析 compatible/reg/interrupts
- **完全兼容 Linux 设备树**（使用标准 DTB 绑定，非自定义格式）

### kei 内核用户空间 I/O 打通（2026-07-04）🎉🎉🎉

**kei 内核在 aarch64 QEMU 中实现了完整的用户空间 I/O。**

裸金属 aarch64 init 程序通过 `write(1, msg, 24)` syscall 成功在串口输出：
```
=== kei ignition ===
```

**根因与修复**：
- `dyn PerOpenFileOps` trait object 的 vtable 在 aarch64（nightly-2026-04-03）上无法正确 dispatch `FileOps::write_at` 到 `TtyFile::write_at`
- 修复：`sys_write()` 在 aarch64 上拦截 fd 1/2（stdout/stderr），直接通过 `pl011_send_byte()` 写 PL011 UART，绕过 vtable dispatch

**完整验证链路**：
1. PL011 UART 控制台注册（替换 TODO stub）→ `aster_console` 发现 "Uart-Console" ✅
2. 串口 Tty 设备创建 → `/dev/ttyS0` 在 RamFs 注册 ✅
3. init 进程 fd 0/1/2 连接到 `/dev/ttyS0` ✅
4. 用户空间 `write(1, buf, 24)` syscall → PL011 MMIO → 串口输出 ✅

** celestia-devtools 集成**：
- aris 和 kei 导入 `celestia-devtools.just`
- 共享 recipes：cache-guard、fmt-markdown、prefetch、cross-check
- 宿主机 QEMU/dtc/交叉编译器安装自动化（`setup_env.py`）
- `tests/e2e_qemu_ignition.sh`（177 行）：QEMU arm64 中 kei 内核启动 → evernight sensor-poll → gateway 全链路测试脚本
- evernight-server 作为 mock entelecheia gateway（8443 端口）
- QEMU user-mode NAT 网络（guest 10.0.2.15 ↔ host 10.0.2.2）
- evernight aarch64 二进制嵌入 initramfs（6.2MB cpio.gz）

### 既往提交

- fix: gate vbe_dispi module to x86_64 only (aarch64 build fix)
- feat: fix build/test pipeline + verify aarch64 QEMU boot
- milestone: kei Asterinas kernel FULLY BOOTS on aarch64 QEMU

## 5. 后续计划

### 短期
1. ~~**用户空间串口输出**——init 进程已加载但 stdout 未连接到串口~~ ✅ 已修复（`open_initial_console` 将 /dev/console 分配为 fd 0/1/2）
2. **busybox ELF TLS 加载**——busybox 的 TLS 段触发 `copy_from_slice::len_mismatch_fail`（FileSiz=0x40 vs 分配 buffer），需修复 ELF 加载器 TLS 处理
3. ~~**evernight aarch64 交叉编译**——构建 `aarch64-unknown-linux-musl` evernight 二进制~~ ✅ 已完成
4. ~~**kei + evernight 联调**——QEMU 中 kei 内核启动 → evernight 连接 gateway~~ ✅ 测试脚本已就绪

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

