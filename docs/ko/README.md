<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>산업용 엣지 게이트웨이를 위한 Rust 커널 — Linux 시스템 콜 ABI, ARM64 / RISC-V.</strong></p>

<div align="center">

[![License: SySL](https://img.shields.io/badge/license-SySL%201.0-blue)](../../LICENSE)
[![License: MPL-2.0](https://img.shields.io/badge/vendored-MPL--2.0-blue)](../../LICENSE-MPL)
[![Checks](https://img.shields.io/github/actions/workflow/status/celestia-island/kei/ci.yml)](https://github.com/celestia-island/kei/actions/workflows/ci.yml)

</div>

<div align="center">

[English](../en/README.md) ·
[简体中文](../zh-Hans/README.md) ·
[繁體中文](../zh-Hant/README.md) ·
[日本語](../ja/README.md) ·
**한국어** ·
[Français](../fr/README.md) ·
[Español](../es/README.md) ·
[Русский](../ru/README.md) ·
[العربية](../ar/README.md)

</div>

## 소개

KEI는 ARM64 / RISC-V 엣지 **게이트웨이**용 Rust 커널로, **Linux 시스템 콜 ABI**를 구현합니다(MMU 필요). **RTOS가 아니며** 마이크로컨트롤러 타깃은 없습니다. 마이크로컨트롤러 계층은 `kei` 라이브러리(`packages/kei/`)가 담당합니다.

KEI는 [Asterinas](https://github.com/asterinas/asterinas)에서 포크되어 시작되었으며, 이제 자체 vendored 트리를 보유합니다(**업스트림을 추적하지 않습니다**).

## 상태

KEI는 **연구용 커널**입니다. 출시된 Celestia 서비스는 이를 사용하지 않으며, 커널을 소비하는 제품도 없습니다.

- **실시간 기능은 계획 단계이며 아직 구현되지 않았습니다.** 고해상도 타이머와 페이지 잠금은 미해결 부채로 기록되어 있습니다. 이 커널은 RTOS가 아니며 유계 지연을 주장하지 않습니다.
- **드라이버 계약은 kei에서 아직 검증되지 않았습니다.** `evernight-appliance`의 rig는 동일한 ABI 스위트를 Linux(기준)와 kei 양쪽에 실행하지만, **지금까지 기록된 것은 Linux 기준뿐입니다**.

제품 소비자가 있는 부분은 `packages/kei/`의 `kei` 라이브러리입니다.

## 저장소 내용

| 컴포넌트 | 위치 | 설명 |
|---------|------|------|
| **KEI 커널** | workspace root | ARM64/RISC-V 엣지 게이트웨이용 Rust 커널. Linux 시스템 콜 ABI(MMU 필요). RTOS 아님. |
| **kei 라이브러리** | `packages/kei/` | embassy용 `#![no_std]` 라이브러리 |

## 빠른 시작

```bash
just build        # 기본 보드 빌드
just test-all     # QEMU 부트 테스트
```

## 라이선스

KEI 자체 코드는 SySL-1.0. 도입된 Asterinas 코드는 MPL-2.0.
