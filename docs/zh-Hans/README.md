<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>面向工业边缘网关的 Rust 内核 —— Linux 系统调用 ABI，ARM64 与 RISC-V。</strong></p>

<div align="center">

[![License: SySL](https://img.shields.io/badge/license-SySL%201.0-blue)](../../LICENSE)
[![License: MPL-2.0](https://img.shields.io/badge/vendored-MPL--2.0-blue)](../../LICENSE-MPL)
[![Checks](https://img.shields.io/github/actions/workflow/status/celestia-island/kei/ci.yml)](https://github.com/celestia-island/kei/actions/workflows/ci.yml)

</div>

<div align="center">

[English](../en/README.md) ·
**简体中文** ·
[繁體中文](../zh-Hant/README.md) ·
[日本語](../ja/README.md) ·
[한국어](../ko/README.md) ·
[Français](../fr/README.md) ·
[Español](../es/README.md) ·
[Русский](../ru/README.md) ·
[العربية](../ar/README.md)

</div>

## 简介

KEI 是面向 ARM64 与 RISC-V **边缘网关**的 Rust 内核。它实现 **Linux 系统调用 ABI**，为 Linux 编写的网关服务可原样运行，但**需要 MMU**。它**不是 RTOS**，也没有微控制器目标。

微控制器一侧由 `kei` 库（`packages/kei/`）单独承担——面向 embassy 传感器节点的 `#![no_std]` 库。两层共用同一份契约：同一个硬件 manifest 与同一套 wire 协议。

KEI 起初 fork 自 [Asterinas（星绽）](https://github.com/asterinas/asterinas)，现已持有自己的 vendored 代码树，**不再跟随上游**。

```mermaid
flowchart TB
    subgraph Gateway["KEI 内核 —— 网关层"]
        KERN["Linux 系统调用 ABI\nARM64 / RISC-V"]
        NET["网络栈\nsmoltcp"]
    end
    subgraph Sensors["传感器节点 —— MCU 层"]
        EMB["embassy 固件\n使用 kei no_std 库"]
    end
    Sensors -->|"kei 通信协议\n(UART / RS-485)"| Gateway
    Gateway -->|"WebSocket / MQTT"| CLOUD["云平台"]
```

## 仓库内容

| 组件 | 位置 | 说明 |
|------|------|------|
| **KEI 内核** | workspace root | 面向 ARM64/RISC-V 边缘网关的 Rust 内核。Linux 系统调用 ABI（需 MMU）、virtio-gpu、帧缓冲、网络栈。不是 RTOS，无 MCU 目标。 |
| **kei 库** | `packages/kei/` | 面向 embassy 传感器节点的 `#![no_std]` 库 |

## 快速开始

**内核：**
```bash
just build        # 构建默认板卡（NanoPi R3S）
just test-all     # 在 QEMU 中启动测试所有架构
```

**库：**
```bash
cd packages/kei
cargo test --all-features
cargo run --example host_demo
```

## 许可证

KEI 自身代码适用 SySL-1.0。引入的 Asterinas 代码适用 MPL-2.0。
详见 [LICENSE](../../LICENSE) 和 [LICENSE-MPL](../../LICENSE-MPL)。
