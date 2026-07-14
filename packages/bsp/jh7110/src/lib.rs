//! StarFive JH7110 BSP — VisionFive 2 (RISC-V 64).
//!
//! **Status (2026-07-14): skeleton — no drivers implemented yet.**
//!
//! Planned support. Drivers TBD:
//! - JH7110 GPIO
//! - DesignWare GMAC Ethernet
//! - NS16550 UART
//! - DesignWare SPI/I2C
//!
//! Note: riscv64 is Tier 2 in upstream Asterinas, so
//! this BSP may be buildable before ARM64 is merged.
//!
//! See `packages/bsp/README.md` for the BSP completion matrix.

#![no_std]

// Fail loudly if this skeleton BSP ever gets linked into a real kernel build.
// Remove this guard once the first driver (GPIO recommended) lands.
#[cfg(any(feature = "jh7110-bsp", feature = "enable-jh7110", doc))]
const _DOC_GATE: () = ();

#[cfg(all(not(doc), not(feature = "jh7110-bsp"), not(feature = "enable-jh7110"),))]
compile_error!(
    "bsp-jh7110 is a skeleton (no drivers yet). Linking it into a kei kernel will \
     produce a non-functional system. Either implement the first driver (start with GPIO) \
     and remove this `compile_error!`, or do not select this BSP in your board config. \
     See packages/bsp/README.md for the current completion matrix."
);

/// Placeholder init. Never reachable while the `compile_error!` above is in effect.
pub fn init() {}
