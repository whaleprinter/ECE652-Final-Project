.section .text
.global _start
_start:
    li sp, 0x3000   # Core 0's stack starts at 0x3000
    call main
halt:
    j halt
    