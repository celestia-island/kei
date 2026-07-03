<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/kei/master/docs/logo.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>Asterinas ARM64 フォーク —— 産業用 IoT ゲートウェイ向けの独立カーネル</strong></p>

<div align="center">

[![License: SySL](https://img.shields.io/badge/license-SySL%201.0-blue)](../../LICENSE)
[![License: MPL-2.0](https://img.shields.io/badge/vendored-MPL--2.0-blue)](../../LICENSE-MPL)
[![Checks](https://img.shields.io/github/actions/workflow/status/celestia-island/kei/ci.yml)](https://github.com/celestia-island/kei/actions/workflows/ci.yml)

</div>

<div align="center">

[English](../en/README.md) ·
[简体中文](../zhs/README.md) ·
[繁體中文](../zht/README.md) ·
**日本語** ·
[한국어](../ko/README.md) ·
[Français](../fr/README.md) ·
[Español](../es/README.md) ·
[Русский](../ru/README.md) ·
[العربية](../ar/README.md)

</div>

## はじめに

KEI は [asterinas/asterinas](https://github.com/asterinas/asterinas) の独立フォークであり、
ARM64 サポートと産業用 IoT ゲートウェイ向けのボードサポートパッケージ（BSP）を提供します。
[aris](https://github.com/celestia-island/aris) が使用する `kei-kernel.bin` を生成します。

## フォークモデル

KEI は上流を追跡するブランチでは**ありません**。独立したフォークであり、独自のスケジュールで
定期的に上流の変更を取り込みます —— Apple が自社の LLVM フォークで採用しているモデルと同じです。

```mermaid
flowchart LR
    UP["asterinas/asterinas\n（活発な上流）"] -->|vendor-upstream.sh\n数ヶ月ごとにスカッシュ| KEI["kei（本リポジトリ）\n完全に独立"]
    WNY["wanywhn/asterinas\n（arm64-support）"] -->|pull-arm64.sh\n一回限りのスナップショット| KEI
```

KEI は `ostd/src/arch/aarch64/`、`kernel/src/arch/aarch64/`、
`bsp/`、`board/`、`configs/`、`docs/` を独自に保守しています。

## aris との関係

```mermaid
flowchart TB
    subgraph KEI["kei（本リポジトリ）"]
        OSTD["ostd/ — 定期的にベンダー取り込み"]
        KERN["kernel/ — 定期的にベンダー取り込み"]
        BSP["bsp/ — 100% 自作コード"]
        BRD["board/ — 100% 自作コード"]
    end
    subgraph ARIS["aris（ゲートウェイファームウェア）"]
        CORE["packages/core/ — スーパバイザ"]
        BUILDER["packages/builder/ — イメージビルダ"]
        OVL["overlay/ — rootfs ファイル"]
        SCR["scripts/ — ビルド + 書き込み"]
    end
    KEI -->|kei-kernel.bin| ARIS
```

## クイックスタート

```bash
just setup        # Configure git remotes
just vendor       # Absorb latest upstream asterinas (squash)
just pull-arm64   # Pull ARM64 code from wanywhn fork (one-time)
just versions     # Show what upstream versions we're based on
just build        # Build kernel for nanopi-r3s (aarch64)
just test-all     # Boot-test all architectures in QEMU
```

## 各ディレクトリの役割

| ディレクトリ | 由来 | 保守 |
|-----------|--------|-------------|
| `ostd/` | 上流 asterinas | 定期的にベンダー取り込み、バグはその場で修正 |
| `ostd/src/arch/aarch64/` | wanywhn フォーク（PR #3270） | **独立** —— 私たちが管理 |
| `kernel/` | 上流 asterinas | 定期的にベンダー取り込み |
| `kernel/src/arch/aarch64/` | wanywhn フォーク（PR #3270） | **独立** —— 私たちが管理 |
| `osdk/` | 上流 asterinas | 定期的にベンダー取り込み |
| `bsp/` | kei | **100% 自作** —— ボードサポートパッケージ |
| `board/` `configs/` | kei | **100% 自作** —— ボード定義 |
| `scripts/` `docs/` | kei | **100% 自作** —— ツールとドキュメント |

## サポートするアーキテクチャ

| アーキテクチャ | 状態 | QEMU テスト |
|------|--------|-----------|
| x86_64 | 上流 Tier 1 | ✅ q35 |
| aarch64 | kei 保守（PR #3270 由来） | ✅ virt/cortex-a55 |
| riscv64 | 上流 Tier 2 | ⚠️ virt/rv64 |
| loongarch64 | 上流 Tier 3 | ⚠️ virt/max |

## ライセンス

SySL-1.0（Synthetic Source License）が KEI 自身のコードに適用されます —— [LICENSE](../../LICENSE) を参照。ベンダー取り込みの Asterinas コード（`ostd/`、`kernel/`、`osdk/`）は MPL-2.0 のままです —— [LICENSE-MPL](../../LICENSE-MPL) を参照。
