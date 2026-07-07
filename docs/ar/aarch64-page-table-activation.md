# aarch64 Kernel Page Table Activation — Diagnosis

## Status: Root-caused, fix pending (architecture-level change)

The kernel page table is **not activated** on aarch64
(`ostd/src/lib.rs:113-125` skips `activate_kernel_page_table`). This blocks
spawning the first task (kernel stacks live in VMALLOC, which is only mapped
in the inactive `KERNEL_PAGE_TABLE`), which in turn blocks the scheduler,
`first_kthread`, and reaching userspace.

## The real root cause (deeper than the original comment suggested)

The original `ostd/src/lib.rs` comment said the skip was due to a
"structural mismatch with TCR_EL1's TTBR0/TTBR1 split." Investigation shows
the real cause is different and more fundamental:

**The kernel is linked at the identity physical address** (`aarch64.ld`:
`KERNEL_LMA = 0x40000000`, all sections `. = KERNEL_LMA`). This means every
symbol — code addresses, function pointers, vtables, string literals, static
mut pointers — has a virtual address of the form `0x4000_xxxx` (the identity
mapping), **not** the linear-mapping address `0xffff_8000_4000_xxxx`.

The cursor-built `KERNEL_PAGE_TABLE` only contains the linear mapping
(`LINEAR_MAPPING_BASE_VADDR .. +max_paddr`, i.e. `0xffff_8000_xxxx`) and the
frame-metadata mapping. The `KernelPtConfig::TOP_LEVEL_INDEX_RANGE = 256..512`
restricts the cursor to the upper half, so it **cannot** also map the identity
range `0x0..max_paddr`.

Consequence: activating `KERNEL_PAGE_TABLE` (writing its root to TTBR0/TTBR1)
makes the identity mapping vanish. The very next instruction fetch, and every
subsequent data access to a linked symbol, faults:

```
activate_page_table writes TTBR0/TTBR1 = KERNEL_PAGE_TABLE root
  → TLB flush
  → next instruction fetch at current PC (identity VA 0x4026_xxxx)
  → not in new table → Prefetch Abort (EC=0x21, FAR=0x4026xxxx)
  → VBAR_EL1 is still 0 (trap::init_on_cpu hasn't run)
  → jumps to 0x200 → also unmapped → infinite abort loop
```

Setting VBAR_EL1 early (to `trap_vectors` at its linear address) and
migrating the PC to the linear mapping before the switch were both tried.
They get further — the PC runs at `0xffff_8000_xxxx` and the trap handler is
reachable — but the handler and surrounding code still dereference identity
addresses for global data (`FAR=0x4030xxxx` Data Aborts), because **all
linked symbol references are identity VAs**. Only relinking the kernel at the
linear VMA fixes this globally.

## Why x86_64 works

x86_64 uses a single CR3 with no TTBR0/TTBR1 split, and its kernel is linked
at a high VMA (`0xffff_8000_0000_xxxx`) from the start, so symbol references
are already in the upper half that the cursor-built table maps. Activation is
a single `Cr3::write` with no PC migration needed.

## The fix (not yet implemented)

Relink the aarch64 kernel at the linear-mapping VMA so that all symbol
references are upper-half addresses present in `KERNEL_PAGE_TABLE`. This
requires:

1. **`aarch64.ld`**: set `KERNEL_VMA = 0xffff_8000_4000_0000` and link all
   non-boot sections at `KERNEL_VMA + (PA - KERNEL_LMA)`, with `AT(KERNEL_LMA)`
   so the ELF load segments still load at the physical address QEMU delivers
   them to. The `.boot` section stays at the identity PA (it runs before MMU
   enables / before the linear jump).

2. **`bsp_boot.S`**: after enabling the MMU with the boot page table (which
   maps both identity and linear), jump to `bsp_boot_virt` at its **linear**
   address (`bsp_boot_virt + 0xffff_8000_0000_0000`). From that point all
   code runs at upper-half VAs. Set `VBAR_EL1` to `trap_vectors` at its
   linear address too (before any Rust code runs).

3. **`ostd/src/lib.rs:113-125`**: remove the `#[cfg(target_arch="aarch64")]`
   skip of `activate_kernel_page_table`. With the kernel running at linear
   VAs, the switch is a plain TTBR write + TLB flush — no trampoline needed.
   Also un-skip `boot_pt::dismiss` (`lib.rs:149-152`).

4. Verify `activate_page_table` (`ostd/src/arch/aarch64/mm/mod.rs:295`) writes
   the new root to **both** TTBR0 and TTBR1 (it already does — the shared-root
   design). After activation, `reinit_with_linear_mapping` makes the UART
   reachable at its linear address.

This is the same design x86_64 already uses; aarch64 was left half-migrated.

## Secondary blockers (discovered during this investigation)

These block the init path independently of the page table, and were worked
around in `kernel/src/init.rs` (commit `0e45ebb`):

- **`time::init`** → `aster_time::read_start_time().unwrap()` panics:
  `START_TIME` is only set by the time component's `#[init_component]` (RTC
  driver), which is bypassed on aarch64. Kept skipped.
- **`fs::init`** → `vfs::init` → `registry::init` →
  `sysfs::systree_singleton().root().add_child().unwrap()` panics: the sysfs
  singleton isn't ready at that point. Kept skipped.
- **`virtio_component_init_pub` in boot context** → `allocate_major()` uses
  `ostd::sync::Mutex` (WaitQueue-backed), which requires a task context.
  Moved to `first_kthread`.

## Reproduction

```bash
# Apply the activation (remove the skip in ostd/src/lib.rs:113), build, run:
cargo osdk build --target-arch aarch64 --scheme aarch64 --release
qemu-system-aarch64 -cpu cortex-a72 -machine virt,gic-version=3,virtualization=on \
  -m 2G -smp 1 --no-reboot -display none -serial stdio \
  -kernel target/osdk/aster-kernel/aster-kernel-osdk-bin.qemu_elf \
  -device virtio-gpu-device -d int -D /tmp/int.log
# Observe: Prefetch Abort, FAR=0x4026xxxx (identity VA), infinite loop at 0x200.
```
