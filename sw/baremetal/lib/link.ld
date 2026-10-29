/* OCM, 256 KiB at 0xFFFC0000. The FSBL/PMU firmware are long done by the
 * time a program is loaded over JTAG. */
ENTRY(_start)
MEMORY { ocm (rwx) : ORIGIN = 0xFFFC0000, LENGTH = 0x40000 }
SECTIONS
{
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > ocm
    .rodata : { *(.rodata .rodata.*) } > ocm
    .data : { *(.data .data.*) } > ocm
    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss .bss.* COMMON)
        . = ALIGN(16);
        __bss_end = .;
    } > ocm
    .stack (NOLOAD) : ALIGN(16) { . += 0x4000; __stack_top = .; } > ocm
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
