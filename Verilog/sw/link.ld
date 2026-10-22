/* Memory map for SPMD programs (both cores run this one image).
 *
 *   0x0000 - 0x0FFF  code, read-only data and initialized data. This image is
 *                    loaded into both L1I caches (4 KB) and into data memory.
 *   0x1000 - 0x2FFF  .bss (zero-initialized globals; shared between the cores)
 *   0x3000 - 0x37FF  core 1 stack
 *   0x3800 - 0x3FFF  core 0 stack
 *   0x8000_0000      sync unit (uncached I/O, see sync_unit.v)
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0x0;
    .text   : { *(.text.start) *(.text .text.*) }
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
    .data   : { *(.data .data.* .sdata .sdata.*) }
    _image_end = .;
    .bss    : { *(.bss .bss.* .sbss .sbss.* COMMON) }
    _bss_end = .;

    ASSERT(_image_end <= 0x1000, "code + data do not fit the 4 KB instruction cache")
    ASSERT(_bss_end <= 0x3000, "globals overlap the stacks")
}
