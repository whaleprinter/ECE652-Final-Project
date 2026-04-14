OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    /* Instructions start at 0x0 (For your L1I Caches) */
    . = 0x00000000;
    .text : {
        *(.text)
        *(.rodata)
    }

    /* Local C variables (data/bss) start at 0x00000400 to stay out of the way */
    . = 0x00000400; 
    .data : {
        *(.data)
    }
    .bss : {
        *(.bss)
    }
}