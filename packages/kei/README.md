# kei

**A `#![no_std]` embedded bridge library for the Celestia IoT ecosystem.**

`kei` is the shared contract layer between **embassy-based sensor nodes** (bare-metal MCUs) and the **gateway broker** — today `evernight` running on Linux. It provides:

- **Manifest schema** (`kei::manifest`) — hardware descriptions: register maps, alarm rules, station configs, scale transforms. The same schema both sides deserialize.
- **Wire protocol** (`kei::wire`) — a compact binary framing protocol for UART/USB-CDC/SPI between sensor nodes and the gateway.
- **Protocol codecs** (`kei::codec`) — pure encode/decode functions for Modbus, MC Protocol, EtherNet/IP-CIP, CAN — no OS dependency, usable on bare metal.
- **HAL traits** (`kei::hal`) — `Transport` and `SensorDevice` traits that embassy nodes implement against their hardware.

## Quick start (embassy sensor node)

```rust
// On an STM32 / nRF52 / RP2040 running embassy:
use kei::wire::{Node, Frame, MsgType};
use kei::manifest::SensorUnit;

let mut node = Node::new(transport);  // your embassy UART
node.register_station(&station_manifest);

loop {
    let req = node.poll().await;
    let temp = read_adc().await;  // your hardware
    node.telemetry(STATION_ID, REGISTER_TEMP, temp, SensorUnit::Celsius)
        .await;
}
```

## Quick start (gateway side, with evernight)

```rust
// On the evernight gateway (host Linux / kei-kernel):
use kei::wire::{Gateway, Frame};
use kei::manifest::HardwareManifest;

let manifest = HardwareManifest::from_toml_str(&toml_str)?;
let mut gw = Gateway::new(transport);  // serial port

let frame = gw.recv().await?;  // Frame from a sensor node
let telemetry = frame.as_telemetry()?;
println!("station {} register {} = {} {}", telemetry.station_id,
    telemetry.register, telemetry.value, telemetry.unit);
```

## Design principles

1. **`#![no_std]` + `alloc` only** — no std, no tokio, no OS calls. It needs a heap (the wire layer allocates frame buffers), so budget for `alloc` on the target rather than a fixed figure.
2. **Serde everywhere** — manifest types derive `Serialize`/`Deserialize`; wire payloads use `postcard` (compact binary).
3. **Codec ≠ transport** — encode/decode are pure functions returning `Vec<u8>`; the caller owns I/O (embassy async, tokio, kernel IRQ — all work).
4. **Shared schema, independent implementations** — embassy nodes and evernight both deserialize the same `HardwareManifest`, but their runtime converters are separate (no_std can't use closures/`Arc<dyn Fn>`).

## Relationship to the kernel in this repository

This crate is a **separate workspace that does not depend on the kernel**. It builds on
**stable** Rust for `thumbv7em-none-eabi` and `riscv32imc-unknown-none-elf`, and its
`rust-toolchain.toml` declares exactly that, so it resolves the right toolchain from the
directory alone — no kernel checkout and no `rustup` override needed. (The kernel at the
repository root pins a nightly toolchain for `aarch64-unknown-none`; that pin does not
apply here.)

The two are independent artifacts that share a contract rather than code:

| | Kernel (repo root) | This crate (`packages/kei/`) |
|---|---|---|
| Target | ARM64 / RISC-V **gateways**, Linux syscall ABI, MMU required | bare-metal **MCUs**, no MMU |
| Toolchain | nightly, `aarch64-unknown-none` family | stable, `thumbv7em` / `riscv32imc` |
| Role | long-term candidate to replace Linux on the gateway | the MCU-side contract |

## License

SySL-1.0 (Synthetic Source License).
