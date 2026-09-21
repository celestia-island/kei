<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>Un noyau Rust pour les passerelles edge industrielles — ABI d'appels système Linux, ARM64 et RISC-V.</strong></p>

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
**Français** ·
[Español](../es/README.md) ·
[Русский](../ru/README.md) ·
[العربية](../ar/README.md)

</div>

## Introduction

KEI est un noyau Rust pour les **passerelles** edge ARM64 et RISC-V, implémentant l'**ABI des appels système Linux** (MMU requise). Ce n'est **pas** un RTOS et il n'a pas de cible microcontrôleur. La couche microcontrôleur est assurée séparément par la bibliothèque `kei` (`packages/kei/`).

KEI a commencé comme fork d'[Asterinas](https://github.com/asterinas/asterinas) et porte désormais son propre arbre vendored : il **ne suit plus l'amont**.

## État

KEI est un **noyau de recherche**. Aucun service Celestia livré ne l'exécute, et le noyau n'a pas de consommateur en production.

- **Le temps réel est prévu, pas présent.** Les minuteries haute résolution et le verrouillage de pages sont enregistrés comme travaux en attente. Ce noyau n'est pas un RTOS et ne revendique aucune latence bornée.
- **Le contrat de pilotes n'a pas encore été prouvé sur kei.** Le rig d'`evernight-appliance` exécute la même suite d'ABI sur Linux (l'oracle) et sur kei ; **seul l'oracle Linux est enregistré à ce jour**.

La partie qui a des consommateurs en production est la bibliothèque `kei` sous `packages/kei/`.

## Contenu

| Composant | Emplacement | Description |
|-----------|-------------|-------------|
| **Noyau KEI** | racine workspace | Noyau Rust pour passerelles edge ARM64/RISC-V. ABI d'appels système Linux (MMU requise). Pas un RTOS. |
| **Bibliothèque kei** | `packages/kei/` | Bibliothèque `#![no_std]` pour embassy |

## Démarrage rapide

```bash
just build        # Compiler pour la carte par défaut
just test-all     # Test de démarrage QEMU
```

## Licence

Code KEI : SySL-1.0. Code Asterinas importé : MPL-2.0.
