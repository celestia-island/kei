# kei — Project Plan

## Goal

Maintain a production-ready Asterinas ARM64 kernel distribution for industrial IoT gateways.

## Architecture

### Layer Model

```
┌────────────────────────────────────────┐
│  bsp/  (Board Support Packages)         │
│  ├── rk3566    Rockchip RK3566          │
│  ├── bcm2711   Raspberry Pi 4           │
│  └── jh7110    StarFive JH7110          │
│        Provides: GPIO, Ethernet, UART,  │
│        SPI, I2C, Watchdog drivers       │
├────────────────────────────────────────┤
│  patches/arm64/  (ARM64 Architecture)    │
│        Provides: GICv3, MMU, page       │
│        tables, exception handling,      │
│        context switching, timer         │
│        Source: wanywhn/asterinas        │
│        branch: arm64-support (PR #3270) │
├────────────────────────────────────────┤
│  asterinas/asterinas (upstream)         │
│        Provides: ostd framework,        │
│        kernel core, OSDK build tool     │
│        Version: 0.18.0+                 │
└────────────────────────────────────────┘
```

### Source Management

kei tracks three upstream sources:

| Remote | URL | Branch | Role |
|--------|-----|--------|------|
| upstream | asterinas/asterinas | main | Base kernel (ostd + kernel + osdk) |
| arm64 | wanywhn/asterinas | arm64-support | ARM64 architecture patches |
| kei | celestia-island/kei | dev | Our BSP + configs + build infra |

Setup flow:
```
scripts/setup.sh:
  1. Clone asterinas/asterinas → vendor/asterinas/
  2. Fetch wanywhn/asterinas arm64-support
  3. Generate patches/arm64/ from diff
  4. Apply patches on top of vendor/asterinas/
  5. Symlink or copy bsp/ crates into vendor/asterinas/ workspace
```

## Milestones

### M1 — Repository Bootstrap (2026 Q3)
- [x] Repository structure
- [ ] ARM64 patches extracted and versioned
- [ ] `scripts/setup.sh` works (fetch + patch + build env)
- [ ] `scripts/build.sh` produces bootable aarch64 kernel
- [ ] QEMU smoke test passes (arm64 virt machine boots to console)

### M2 — RK3566 BSP (2026 Q3)
- [ ] GPIO driver (ostd device model)
- [ ] stmmac Ethernet driver (DW GMAC / RK GMAC)
- [ ] UART 8250_DW driver
- [ ] WDT (watchdog) driver
- [ ] SPI / I2C master drivers
- [ ] Device tree parsing (FDT → ostd device model)

### M3 — NanoPi R3S Boot (2026 Q4)
- [ ] U-Boot chainloading Asterinas
- [ ] Verified boot chain
- [ ] Console output on debug UART
- [ ] Ethernet link up (dual GbE)
- [ ] Integration test with aris + evernight

### M4 — Multi-arch & Production (2027)
- [ ] RISC-V board support (VisionFive 2)
- [ ] ARM32 (armv7) evaluation
- [ ] OTA kernel update integration with aris-core
- [ ] Performance parity with Linux baseline
- [ ] Track upstream Asterinas ARM64 merge, pivot to official

## Key Design Decisions

1. **No git submodules** — `scripts/setup.sh` fetches upstream sources on demand
2. **Patches as quilt series** — cleaner than maintaining a fork; easy to rebase
3. **BSP as OSDK library crates** — follows Asterinas component model
4. **Board configs in TOML** — same format as aris for tooling consistency
5. **Aarch64 target triple**: `aarch64-unknown-none` (bare metal, no OS)
