# hare no_std Library (formerly the `kei` library)

> **Moved (2026-10):** the library described here began as `packages/kei/` in this
> repo and now lives in the [hare repo](https://github.com/celestia-island/hare). Commands below are updated to run
> from a hare checkout cloned alongside this repo.

The [hare](https://github.com/celestia-island/hare) library (which began life here as the `kei` library, `packages/kei/`) is a `#![no_std]` Rust crate that provides
the shared contract between embassy-based sensor nodes and the gateway broker.

## What it provides

- **Wire protocol** (`hare::wire`) — compact binary framing (magic + length + type + payload + CRC16) for UART/USB-CDC/SPI. Includes `Node` (sensor side) and `Gateway` (broker side) high-level APIs.
- **Manifest schema** (`hare::manifest`) — hardware descriptions: register maps, alarm rules, station configs, scale transforms (Linear / Table interpolation / Polynomial).
- **HAL traits** (`hare::hal`) — `Transport`, `AsyncTransport`, `AddressedTransport` — embassy-implementable abstractions.
- **Protocol type identifiers** (`hare::codec`) — `ProtocolKind` enum and `ProtocolFrame` opaque container.

## Quick start

```bash
cd hare
cargo test --all-features              # 63 tests
cargo bench --bench wire_bench         # criterion benchmarks
cargo run --example host_demo          # host-side wire protocol demo
```

## QEMU demo (Cortex-M4)

The `qemu-mps2/` directory (repo root of the hare checkout) contains a bare-metal firmware that runs
under QEMU's `mps2-an386` machine (Cortex-M4) and demonstrates the wire
protocol end-to-end.

```bash
cd hare/qemu-mps2
cargo build --release --target thumbv7em-none-eabi
qemu-system-arm -M mps2-an386 -cpu cortex-m4 -m 16M \
    -display none -serial stdio \
    -kernel ../target/thumbv7em-none-eabi/release/kei-qemu-mps2
```

(The workspace target dir lives at the hare checkout root, not next to this
member — hence `../target/`.)

A host-side gateway (`examples/host_gateway.rs` in this directory) decodes
the wire frames from QEMU's serial output:

```bash
cargo build -p kei-qemu-mps2 --example host_gateway --target x86_64-unknown-linux-gnu
qemu-system-arm ... | ../target/x86_64-unknown-linux-gnu/debug/examples/host_gateway
```

The directory also ships `./run_demo.sh`, which builds both halves and
wires them together. (Note: as of 2026-11 the script passes `-m 4M` to QEMU,
which mps2-an386 rejects — it requires exactly 16 MiB. Until that is fixed
in the hare repo, use the explicit commands above with `-m 16M`.)

## Using hare in your embassy project

Add to your `Cargo.toml`:

```toml
[dependencies]
hare = { git = "https://github.com/celestia-island/hare.git", branch = "master", default-features = false, features = ["wire", "manifest", "hal"] }
```

Implement `Transport` for your UART, then use `Node`:

```rust
use hare::wire::{Node, Request};
let mut node = Node::new(your_uart_transport, 1); // station_id = 1
loop {
    let req = node.poll(&mut sensor);
    // handle req, send telemetry back
}
```
