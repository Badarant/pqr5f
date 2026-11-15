/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * Minimal link for code-size measurement: no board, no startup, no C library.
 * Regions are generous and the addresses arbitrary - nothing runs, the point is
 * only to let --gc-sections prune and to give the map file section sizes to
 * attribute.
 */
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4M
    RAM (rw) : ORIGIN = 0x20000000, LENGTH = 4M
}

SECTIONS
{
    .text : {
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > ROM

    .data : {
        *(.data .data.*)
    } > RAM

    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } > RAM

    /DISCARD/ : {
        *(.ARM.exidx*)
        *(.ARM.extab*)
        *(.comment)
        *(.note*)
    }
}
