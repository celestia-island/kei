ENTRY(_start)
OUTPUT_ARCH(aarch64)
OUTPUT_FORMAT(elf64-littleaarch64)

KERNEL_LMA = 0x40000000;

PHDRS
{
    boot PT_LOAD FLAGS(7);
    text PT_LOAD FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = KERNEL_LMA;
    __kernel_start = .;

    .boot : {
        *(.boot .boot.*)
    } :boot

    . = ALIGN(4096);
    __etext = .;
    .text : {
        *(.text._start)
        *(.text .text.*)
    } :text

    . = ALIGN(4096);
    __ex_table_start = .;
    __ex_table = .;
    .ex_table : {
        *(.ex_table)
    } :rodata
    __ex_table_end = .;

    __eh_frame = .;
    .rodata : {
        *(.rodata .rodata.*)
        *(.eh_frame_hdr)
    } :rodata
    .eh_frame : {
        *(.eh_frame)
    } :rodata

    . = ALIGN(4096);
    __sinit_array = .;
    .init_array : {
        *(.init_array .init_array.*)
    } :data
    __einit_array = .;

    .got : {
        *(.got .got.*)
    } :data

    .data : {
        *(.data .data.*)
    } :data

    . = ALIGN(4096);
    __cpu_local_start = .;
    .cpu_local : {
        *(.cpu_local .cpu_local.*)
    } :data
    __cpu_local_end = .;

    __bss_start = .;
    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } :data
    __bss_end = .;

    . = ALIGN(4096);
    __kernel_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note .note.*)
        *(.ARM.exidx .ARM.exidx.*)
    }
}
