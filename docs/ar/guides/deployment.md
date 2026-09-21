# kei البناء والنشر

## نظرة عامة

ينتج kei ملف `kei-kernel.bin` — نواة Asterinas المُمكَّنة لـ ARM64. يغطي هذا
الدليل بناء النواة واختبارها في QEMU ونشرها على الأجهزة الفعلية.

## خط أنابيب البناء

```mermaid
flowchart LR
    SRC["Source\npackages/ostd, kernel, packages/bsp"] -->|"cargo osdk build\n(scripts/build.py)"| BIN["kei-kernel.bin"]
    BIN --> QEMU["QEMU Test\n(virt/cortex-a72)"]
    QEMU -->|passes| PACK["Package\n(DTB + initramfs)"]
    PACK --> FLASH["Flash SD card"]
    FLASH --> BOARD["NanoPi R3S"]
```

## المتطلبات الأساسية

- **المضيف**: Linux x86_64 أو ARM64
- **Rust**: nightly-2026-05-01 مع هدف `aarch64-unknown-none`
- **QEMU**: ≥ 8.0 لآلة virt مع cortex-a72
- **just**: `cargo install just`

## بناء سريع

```bash
# Stage the shared devtools recipes once (.just/ is gitignored)
just fetch

# One-time setup
just setup        # Configure git remotes

# Build for the NanoPi R3S
just build        # Builds kei-kernel.bin for aarch64/armv8

# Run QEMU boot tests
just test-all     # Boot-tests all supported architectures
```

## الترجمة المتقاطعة

للترجمة المتقاطعة من x86_64 إلى aarch64:

```bash
# The ARM64 target is declared in rust-toolchain.toml, so rustup installs it with
# the toolchain; adding it by hand is:
rustup target add aarch64-unknown-none

# Install GCC cross-toolchain (distribution-dependent)
# Ubuntu / Debian:
sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu

# Build. The kernel is produced through OSDK (it needs the initramfs packed and a
# nightly cargo on PATH), so use the build script rather than a bare `cargo build`:
python3 scripts/build.py nanopi-r3s
```

ملف النواة الثنائي هو صورة ARM64 خام (بروتوكول إقلاع Linux)، وليس ELF. يتم
الإقلاع مباشرة من U-Boot عبر أمر `booti`.

## اختبار QEMU

اختبر النواة في QEMU قبل النشر على العتاد:

```mermaid
flowchart TB
    subgraph Host["الجهاز المضيف"]
        KERN["kei-kernel.bin"]
        DTB["board.dtb"]
        QEMU["QEMU\n(virt, cortex-a72)"]
    end
    KERN --> QEMU
    DTB --> QEMU
    QEMU -->|"serial output\n(logged)"| LOG["سجل وحدة التحكم"]
    QEMU -->|"exit 0 = pass"| RESULT["نتيجة الاختبار"]
```

### مصفوفة الاختبار

| آلة QEMU | CPU | RAM | الحالة | الأمر |
|-------------|-----|-----|--------|---------|
| virt | cortex-a72 | 2GB | ✅ أساسي | `just test` |
| virt | cortex-a72 | 2GB | 🔲 مخطط | — |
| virt | max | 4GB | 🔲 مخطط | — |
| sbsa-ref | max | 4GB | 🔲 مخطط | — |

```bash
# Run the primary test target
just test

# Manual QEMU invocation
qemu-system-aarch64 \
  -machine virt,gic-version=3 \
  -cpu cortex-a72 \
  -m 2G \
  -kernel target/output/nanopi-r3s/kei-kernel.bin \
  -nographic
```

## النشر الفعلي

### NanoPi R3S

نشر kei على NanoPi R3S فعلي:

```mermaid
flowchart TB
    subgraph Build["جهاز البناء"]
        KERN["kei-kernel.bin"]
        DTB["board.dtb"]
        INIT["initramfs.cpio.gz"]
    end
    subgraph Deploy["النشر"]
        IMG["sdcard.img"]
        SD["بطاقة SD"]
        BOARD["NanoPi R3S"]
    end
    KERN --> IMG
    DTB --> IMG
    INIT --> IMG
    IMG -->|"dd / just image"| SD
    SD --> BOARD
```

### النسخ على بطاقة SD

```bash
# Build the complete firmware image (includes kei-kernel.bin)
just build board nanopi-r3s

# Assemble the SD card image (borrows U-Boot + GPT from an Armbian reference)
just image ARMBIAN_IMG=/path/to/armbian.img

# Flash to SD card
sudo dd if=target/output/nanopi-r3s/sdcard.img of=/dev/sdX bs=4M status=progress
sync
```

### تكرار بدون إعادة نسخ

النسخ لمرة واحدة أعلاه هو **آخر** نسخة كاملة مطلوبة. ملف `boot.scr` المرفق يدعم
مساري تكرار لا يلمسان GPT ولا منطقة U-Boot:

#### الإقلاع عبر TFTP (موصى به للعمل على المنصة)

مع `kei_netboot=1` (الافتراضي في `armbianEnv.txt`)، يجلب U-Boot النواة وDTB
وinitramfs عبر TFTP ويعود إلى النسخة على بطاقة SD عند تعذر الوصول إلى الخادم.

إعداد لمرة واحدة على مضيف البناء:

```bash
# Serve /srv/tftp, e.g. with tftpd-hpa:
sudo apt install tftpd-hpa
sudo install -d -o "$USER" /srv/tftp/kei
```

إعدادات اللوحة (مرفقة افتراضيًا في `configs/board/nanopi-r3s/armbianEnv.txt`):

```
kei_netboot=1
kei_tftp_prefix=kei
serverip=192.0.2.74   # build host running the TFTP server — adjust to your LAN
```

حلقة التكرار:

```bash
python3 scripts/build.py nanopi-r3s   # rebuild kernel + DTB
scripts/push_netboot.sh               # copy artifacts into the TFTP root
# reset the board — U-Boot fetches kei over TFTP
```

للدفع إلى خادم TFTP بعيد بدلًا من مجلد محلي:

```bash
KEI_TFTP_DEST=user@host:/srv/tftp scripts/push_netboot.sh
```

#### تحديث بطاقة SD في مكانها (دون اتصال)

عندما لا تكون اللوحة على شبكة البناء المحلية، حدّث بطاقة (أو صورة) موجودة في
مكانها — تُستبدل الملفات تحت `/boot/` فقط:

```bash
scripts/update_sdcard_kernel.sh --image target/output/nanopi-r3s/sdcard.img
# or, with the card in a reader on this host:
sudo scripts/update_sdcard_kernel.sh --device /dev/sdX
```

### التحقق من الإقلاع

بعد إدخال بطاقة SD وتشغيل الطاقة، اتصل عبر USB-TTL التسلسلي (1500000 باود،
8N1):

```
U-Boot 2024.01 (Jan 01 2024 - 00:00:00 +0000)
...
## Loading kernel from mmc 0:1
   Image Name:   kei-kernel
   Image Type:   AArch64 Linux Kernel Image
   Data Size:    4194304 Bytes = 4 MiB
   Load Address: 00000000
   Entry Point:  00000000
## Flattened Device Tree blob at 44000000
   Booting using the fdt blob at 0x44000000

kei-kernel booting...
[KEI] initialising GICv3...
[KEI] initialising ARM Generic Timer...
[KEI] starting SMP...
[KEI] 4 cores online
...
```

### ترتيب الإقلاع

```mermaid
flowchart TB
    ROM["Mask ROM"] --> SPL["U-Boot SPL"]
    SPL --> TPL["U-Boot Proper"]
    TPL -->|"load kernel + DTB\nfrom mmc"| KEI["kei-kernel.bin"]
    KEI -->|"Transfer to EL1"| INIT["kei init\n(مساحة المستخدم)"]
```

## استكشاف الأخطاء

| العَرَض | السبب المحتمل | الإجراء |
|---------|-------------|--------|
| لا يوجد إخراج تسلسلي | معدل باود خاطئ | استخدم 1500000، وليس 115200 |
| فشل تهيئة GICv3 | نوع آلة QEMU | استخدم `virt,gic-version=3` |
| فشل SMP | PSCI مفقود في DTB | تحقق من عقدة `/cpus` في شجرة الجهاز |
| Kernel panic | خطأ في كود طبقة الهندسة المعمارية | تدقيق `packages/ostd/src/arch/aarch64/` |
| U-Boot لا يجد النواة | إزاحة قسم خاطئة | تحقق من الإزاحة في `boot.scr` |
