<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>Un núcleo Rust para pasarelas edge industriales — ABI de llamadas al sistema Linux, ARM64 y RISC-V.</strong></p>

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
**Español** ·
[Русский](../ru/README.md) ·
[العربية](../ar/README.md)

</div>

## Introducción

KEI es un núcleo Rust para **pasarelas** edge ARM64 y RISC-V que implementa la **ABI de llamadas al sistema de Linux** (requiere MMU). **No es un RTOS** y no tiene objetivo para microcontroladores. La capa de microcontrolador la cubre aparte la biblioteca `kei` (`packages/kei/`).

KEI comenzó como un fork de [Asterinas](https://github.com/asterinas/asterinas) y ahora mantiene su propio árbol vendored: **ya no sigue el upstream**.

## Estado

KEI es un **núcleo de investigación**. Ningún servicio de Celestia ya entregado se ejecuta sobre él, y el núcleo no tiene consumidores en producción.

- **El tiempo real está previsto, no presente.** Los temporizadores de alta resolución y el bloqueo de páginas figuran como trabajo pendiente. Este núcleo no es un RTOS y no afirma latencia acotada.
- **El contrato de controladores aún no se ha demostrado en kei.** El rig de `evernight-appliance` ejecuta la misma suite de ABI sobre Linux (el oráculo) y sobre kei; **hasta ahora solo existe el oráculo de Linux**.

La parte con consumidores en producción es la biblioteca `kei` en `packages/kei/`.

## Contenido

| Componente | Ubicación | Descripción |
|-----------|-----------|-------------|
| **Núcleo KEI** | raíz workspace | Núcleo Rust para pasarelas edge ARM64/RISC-V. ABI de llamadas al sistema Linux (requiere MMU). No es un RTOS. |
| **Biblioteca kei** | `packages/kei/` | Biblioteca `#![no_std]` para embassy |

## Inicio rápido

```bash
just build        # Compilar para placa por defecto
just test-all     # Prueba de arranque QEMU
```

## Licencia

Código KEI: SySL-1.0. Código Asterinas importado: MPL-2.0.
