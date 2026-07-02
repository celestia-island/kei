# ARM64 Support Status

## Upstream

| Item | Status |
|------|--------|
| PR | [asterinas#3270](https://github.com/asterinas/asterinas/pull/3270) |
| Author | [@wanywhn](https://github.com/wanywhn) |
| Branch | [wanywhn/asterinas:arm64-support](https://github.com/wanywhn/asterinas/tree/arm64-support) |
| Review | In progress |
| Estimated merge | 2026 Q3-Q4 |

## What's Included (arm64-support branch)

| Component | Status | Notes |
|-----------|--------|-------|
| `ostd/src/arch/aarch64/` | ✅ | Architecture module |
| GICv3 interrupt controller | ✅ | ARM Generic Interrupt Controller v3 |
| ARM MMU / page tables | ✅ | 4-level paging, TTBR0/1 |
| Exception handling | ✅ | EL1h synchronous/IRQ/FIQ/SError |
| Context switching | ✅ | Task switching, FPU save/restore |
| Generic Timer | ✅ | ARM architected timer (EL1 physical) |
| UART console | ✅ | PL011 / 8250_DW |
| Device tree (FDT) | ✅ | Basic DT parsing |
| SMP / multi-core | ⚠️ | PSCI-based, WIP |
| VirtIO drivers | ⚠️ | Network and block, limited testing |

## kei Additions (on top of arm64-support)

| Component | Status | Notes |
|-----------|--------|-------|
| `bsp/rk3566/` — GPIO | 🔲 | Rockchip GRF pinctrl |
| `bsp/rk3566/` — Ethernet | 🔲 | stmmac / RK GMAC |
| `bsp/rk3566/` — WDT | 🔲 | DW watchdog timer |
| `bsp/rk3566/` — SPI/I2C | 🔲 | DW SSI / RK3x I2C |
| `bsp/bcm2711/` | 🔲 | Raspberry Pi 4 |
| `bsp/jh7110/` | 🔲 | VisionFive 2 (RISC-V) |

## Build Target

```
Architecture:  aarch64
Target triple: aarch64-unknown-none
Toolchain:     nightly-2026-04-03
Components:    rust-src, rustc-dev, llvm-tools-preview
Kernel binary: ELF, stripped
Boot method:   U-Boot (via booti)
```

## Testing

| Platform | Status | Notes |
|----------|--------|-------|
| QEMU virt (arm64) | 🔲 | Boot to console, basic driver test |
| QEMU virt (arm64) + VirtIO | 🔲 | Network and block device test |
| NanoPi R3S (RK3566) | 🔲 | Physical boot test |
| OrangePi 3B (RK3566) | 🔲 | Second board validation |

## Merge Strategy

1. `wanywhn/asterinas:arm64-support` → `asterinas/asterinas:main` (upstream merge)
2. Once merged, kei switches from fork to official release
3. kei continues to maintain BSP crates and board configs as an add-on layer
