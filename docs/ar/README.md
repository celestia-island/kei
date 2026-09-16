<p align="center"><img src="https://raw.githubusercontent.com/celestia-island/docs.celestia.world/dev/res/logo/kei.webp" alt="KEI" width="240" /></p>

<h1 align="center">KEI</h1>

<p align="center"><strong>نواة بـ Rust لبوابات الحافة الصناعية — ABI استدعاءات نظام Linux، ARM64 و RISC-V.</strong></p>

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
[Русский](../ru/README.md) ·
**العربية**

</div>

## مقدمة

KEI نواة بـ Rust لـ**بوابات** الحافة ARM64 و RISC-V، تطبّق **ABI استدعاءات نظام Linux** (تتطلب MMU). **ليست RTOS** وليس لها هدف للمتحكمات الدقيقة. طبقة المتحكمات الدقيقة تتولاها مكتبة `kei` (`packages/kei/`) بشكل منفصل.

بدأ KEI كتفريعة من [Asterinas](https://github.com/asterinas/asterinas) ويحمل الآن شجرة vendored خاصة به: **لم يعد يتابع المصدر upstream**.

## الحالة

KEI **نواة بحثية**. لا توجد خدمة Celestia مُسلَّمة تعمل عليها، وليس للنواة مستهلك في المنتجات.

- **دعم الزمن الحقيقي مخطط له ولم يُنفَّذ بعد.** مؤقتات الدقة العالية وقفل الصفحات مسجَّلة كديون قائمة. هذه النواة ليست RTOS ولا تدّعي زمن استجابة محدودًا.
- **لم يُثبَت عقد برامج التشغيل على kei بعد.** يشغّل منصّة الاختبار في `evernight-appliance` مجموعة ABI نفسها على Linux (المرجع) وعلى kei؛ **ولم يُسجَّل حتى الآن سوى مرجع Linux**.

الجزء الذي له مستهلكون في المنتجات هو مكتبة `kei` داخل `packages/kei/`.

## المحتويات

| المكون | الموقع | الوصف |
|--------|--------|------|
| **نواة KEI** | جذر workspace | نواة بـ Rust لبوابات الحافة ARM64/RISC-V. ABI استدعاءات نظام Linux (تتطلب MMU). ليست RTOS. |
| **مكتبة kei** | `packages/kei/` | مكتبة `#![no_std]` لـ embassy |

## البدء السريع

```bash
just build        # بناء للوحة الافتراضية
just test-all     # اختبار إقلاع QEMU
```

## الترخيص

كود KEI: SySL-1.0. كود Asterinas المستورد: MPL-2.0.
