<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>Ядро на Rust для промышленных edge-шлюзов — ABI системных вызовов Linux, ARM64 и RISC-V.</strong></p>

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
[한국어](../ko/README.md) ·
[Français](../fr/README.md) ·
[Español](../es/README.md) ·
**Русский** ·
[العربية](../ar/README.md)

</div>

## Введение

KEI — ядро на Rust для edge-**шлюзов** ARM64 и RISC-V, реализующее **ABI системных вызовов Linux** (требуется MMU). Это **не RTOS**, и цели для микроконтроллеров нет. Уровень микроконтроллеров отдельно закрывает библиотека `kei` (`packages/kei/`).

KEI начинался как форк [Asterinas](https://github.com/asterinas/asterinas) и теперь несёт собственное vendored-дерево: **upstream больше не отслеживается**.

## Статус

KEI — **исследовательское ядро**. Ни один выпущенный сервис Celestia на нём не работает, и потребителей в продуктах у ядра нет.

- **Реальное время запланировано, но не реализовано.** Таймеры высокого разрешения и блокировка страниц числятся в незакрытых долгах. Это ядро не RTOS и не заявляет ограниченную задержку.
- **Контракт драйверов на kei пока не доказан.** Стенд `evernight-appliance` прогоняет один и тот же набор ABI по Linux (эталон) и по kei; **на сегодня записан только эталон Linux**.

Потребители в продуктах есть у библиотеки `kei` в `packages/kei/`.

## Содержимое

| Компонент | Расположение | Описание |
|-----------|-------------|----------|
| **Ядро KEI** | корень workspace | Ядро на Rust для edge-шлюзов ARM64/RISC-V. ABI системных вызовов Linux (требуется MMU). Не RTOS. |
| **Библиотека kei** | `packages/kei/` | `#![no_std]` библиотека для embassy |

## Быстрый старт

```bash
just build        # Сборка для платы по умолчанию
just test-all     # Загрузочный тест QEMU
```

## Лицензия

Код KEI: SySL-1.0. Импортированный код Asterinas: MPL-2.0.
