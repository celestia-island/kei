# aarch64 User-Space Init Page Fault — Diagnosis

## Status: Root-caused to musl init stack corruption; exact trigger pending

After the kernel page table activation (`dfd7324`) and the ELF loader /
TLS / run_user fixes (`c7ca569`–`b0d09a1`), the kernel successfully loads
busybox `/init` into EL0 and starts executing it. The init process reaches
musl's `__libc_start_main` and early initialization, but then page-faults
in a loop and never reaches a usable shell.

## Symptom

```
[trap] unhandled user pf: elr=0x450408 far=0xfffffff23a20 x0=0x300 x1=0xfffffff23a20
       x8=0x71 x20=0x5e8000 x21=0x7840407878404078 x29=0x7ffffff91d00 x30=0x415434
[trap]   tpidr_el0=0x7ffffeffe8a0 sp_el0=0x7ffffff91d00
```

- `elr=0x450408` / `0x4503dc` — a tight pair of `str x4,[x1]` / `str w4,[x1]`
  instructions in busybox (a table-fill loop). These are reached via many
  call paths.
- `x1 = 0xfffffff23a20` — a kernel-range address (bit 47 set). This is the
  faulting store target. The high 16 bits vary per run (ASLR-linked), but
  bit 47 is always set.
- `x8 = 0x71` = 113 = `clock_gettime` syscall number (the fault happens on
  the musl `clock_gettime` call path).
- `x21 = 0x7840407878404078` — a callee-saved register holding a repeated
  byte pattern (`78 40 40 78`), **not** a valid pointer and **not** present
  anywhere in busybox's static image.

## What's NOT the cause (verified)

- **TPIDR_EL0 is correct**: `0x7ffffeffe8a0` matches the `tp` the kernel
  set in `setup_tls` (`[tls] TCB: ... tp=0x7ffffeffe8a0`). musl's
  `__pthread_self() = TPIDR_EL0 - 0x740 = 0x7ffffeffe160` is a valid in-block
  address.
- **SP_EL0 is correct**: a normal user-stack address.
- **AT_RANDOM is set**: `init_stack/mod.rs:277` sets it from
  `generate_random_for_aux_vec`. AT_NULL is auto-appended.
- **auxv has the required entries**: AT_PAGESZ, AT_PHDR, AT_PHNUM, AT_PHENT,
  AT_ENTRY, AT_SECURE, AT_RANDOM.
- **TLS block layout** (b0d09a1): pthread_size=0x800 ≥ musl's 0x740; .tdata
  (40 bytes) is copied from the LOAD segment; TCB self/dtv fields are set.
- **The pattern `78 40 40 78` is not in busybox's file image** — so x21's
  value is produced at runtime, not loaded from static data.
- **Disabling TLS makes it worse**: with `setup_tls` returning `None`
  (TPIDR_EL0=0), busybox faults even earlier at `rseq` (syscall 293,
  far=0x18). So TLS being present but slightly wrong is better than absent.

## What IS wrong (the smoking gun)

The user-space **stack is corrupted** during musl init:

1. The frame-chain walk from the faulting `x29` returns "caller" addresses
   `0x415434, 0x418dc0, 0x481c20, 0x450ad0, 0x45107c, 0x404bdc, 0x400670`.
2. **All of these addresses contain `udf #0`** (permanently-undefined
   instructions) in busybox's image — they are data/padding regions, not
   code. Real return addresses can't land here.
3. The callee-saved `x21 = 0x7840407878404078` is likewise garbage restored
   from a smashed stack.

So something during musl's early init writes past the end of a stack buffer,
overwriting saved registers and return addresses. The subsequent `str` to
the corrupted `x1` is just the first visible fault.

## gdb caveat

Under `qemu -gdb -S` (start paused) + gdb-multiarch, the fault does **not**
reproduce the same way: at `0x450408`, x1 is a normal stack address
(`0x7ffffff...`) and x8=`0x5e1000` (not 0x71). The timing/execution path
differs under the debugger, so single-stepping hasn't pinpointed the
overwrite. A non-intrusive method (watchpoint on the stack region, or
tracing musl's `__init_tls`/`__copy_tls`/`__init_tp`) is needed.

## Next steps (for whoever picks this up)

1. **Get a symbolicated musl**: rebuild busybox against musl with debug
   symbols (or extract musl's `__init_tls`/`__copy_tls`/`__init_tp`/`
   __libc_start_main` aarch64 sources) and map the call chain
   `0x400670 ← 0x404bdc ← 0x45107c ← 0x450ad0 ← 0x481c20 ← 0x418dc0 ← 0x415434`
   to function names. The overwrite is in one of these.
2. **Watchpoint the stack**: set a hardware write watchpoint on the stack
   slot that holds the callee-saved x21 (or x29) immediately after
   `__libc_start_main`'s prologue, and let it run un-intrusively. The
   watchpoint fires at the exact overwrite instruction.
3. **Compare with Linux**: run the same busybox under real Linux aarch64
   with `strace -v` and dump the initial stack/auxv/TLS layout; diff
   against what kei provides. The divergence points at the bug.
4. **Suspect areas in kei**: the TLS_ABOVE_TP layout math in `setup_tls`
   (`load_elf.rs:546`), the `write_bytes`/stack-pointer arithmetic in
   `init_stack/mod.rs`, or a missing/wrong aux entry that makes musl's
   init compute a bad size/offset.

The kernel infrastructure (page table, scheduler, ELF loader, syscall
dispatch, user/kernel transitions) is all working — the init process
reaches EL0 and executes real musl code. This is purely a user-space ABI
fidelity issue in the init handoff.
