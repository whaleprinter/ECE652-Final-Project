.section .text
.global _start
_start:
    li sp, 0x4000   # Core 1's stack starts at 0x4000
    call main
halt:
    j halt
    