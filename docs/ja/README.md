<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>産業用エッジゲートウェイ向けの Rust カーネル — Linux システムコール ABI、ARM64 / RISC-V。</strong></p>

<div align="center">

[![License: SySL](https://img.shields.io/badge/license-SySL%201.0-blue)](../../LICENSE)
[![License: MPL-2.0](https://img.shields.io/badge/vendored-MPL--2.0-blue)](../../LICENSE-MPL)
[![Checks](https://img.shields.io/github/actions/workflow/status/celestia-island/kei/ci.yml)](https://github.com/celestia-island/kei/actions/workflows/ci.yml)

</div>

<div align="center">

[English](../en/README.md) ·
[简体中文](../zh-Hans/README.md) ·
[繁體中文](../zh-Hant/README.md) ·
**日本語** ·
[한국어](../ko/README.md) ·
[Français](../fr/README.md) ·
[Español](../es/README.md) ·
[Русский](../ru/README.md) ·
[العربية](../ar/README.md)

</div>

## 概要

KEI は ARM64 / RISC-V のエッジ**ゲートウェイ**向け Rust カーネルで、**Linux システムコール ABI** を実装しています（MMU 必須）。**RTOS ではなく**、マイコン向けターゲットはありません。

KEI は [Asterinas](https://github.com/asterinas/asterinas) からのフォークとして始まり、現在は独自の vendored ツリーを保持しています（**上流は追跡していません**）。

## リポジトリ内容

| コンポーネント | 場所 | 説明 |
|---------------|------|------|
| **KEI カーネル** | workspace root | ARM64/RISC-V エッジゲートウェイ向け Rust カーネル。Linux システムコール ABI（MMU 必須）。RTOS ではない。 |
| **kei ライブラリ** | `packages/kei/` | embassy 向け `#![no_std]` ライブラリ |

## クイックスタート

```bash
just build        # デフォルトボード向けビルド
just test-all     # QEMU ブートテスト
```

## ライセンス

KEI 独自コードは SySL-1.0。導入 Asterinas コードは MPL-2.0。
