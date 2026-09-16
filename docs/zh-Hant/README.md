<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>面向工業邊緣閘道的 Rust 核心 —— Linux 系統呼叫 ABI，ARM64 與 RISC-V。</strong></p>

<div align="center">

[![License: SySL](https://img.shields.io/badge/license-SySL%201.0-blue)](../../LICENSE)
[![License: MPL-2.0](https://img.shields.io/badge/vendored-MPL--2.0-blue)](../../LICENSE-MPL)
[![Checks](https://img.shields.io/github/actions/workflow/status/celestia-island/kei/ci.yml)](https://github.com/celestia-island/kei/actions/workflows/ci.yml)

</div>

<div align="center">

[English](../en/README.md) ·
[简体中文](../zh-Hans/README.md) ·
**繁體中文** ·
[日本語](../ja/README.md) ·
[한국어](../ko/README.md) ·
[Français](../fr/README.md) ·
[Español](../es/README.md) ·
[Русский](../ru/README.md) ·
[العربية](../ar/README.md)

</div>

## 簡介

KEI 是面向 ARM64 與 RISC-V **邊緣閘道**的 Rust 核心，實作 **Linux 系統呼叫 ABI**（需 MMU）。它**不是 RTOS**，也沒有微控制器目標。微控制器一側由 `kei` 程式庫（`packages/kei/`）單獨承擔。

KEI 起初 fork 自 [Asterinas（星綻）](https://github.com/asterinas/asterinas)，現已持有自己的 vendored 程式碼樹，**不再跟隨上游**。

## 倉庫內容

| 組件 | 位置 | 說明 |
|------|------|------|
| **KEI 核心** | workspace root | 面向 ARM64/RISC-V 邊緣閘道的 Rust 核心。Linux 系統呼叫 ABI（需 MMU）。不是 RTOS。 |
| **kei 庫** | `packages/kei/` | 面向 embassy 的 `#![no_std]` 庫 |

## 快速開始

```bash
just build        # 構建預設板卡
just test-all     # QEMU 啟動測試
```

## 授權條款

KEI 自身程式碼適用 SySL-1.0。引入的 Asterinas 程式碼適用 MPL-2.0。
