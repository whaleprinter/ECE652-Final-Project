# Startup code shared by both cores (SPMD: both run the same image).
# Each core reads its id from the sync unit, takes its own 2 KB stack below
# 0x4000, calls main(), and reports main's return value as its exit code.

    .section .text.start
    .global _start
_start:
    li   t0, 0x80000000     # sync unit
    lw   a0, 0(t0)          # CORE_ID
    li   sp, 0x4000         # core 0: 0x3800-0x3FFF, core 1: 0x3000-0x37FF
    slli t1, a0, 11
    sub  sp, sp, t1
    call main
    li   t0, 0x80000000
    sw   a0, 0x14(t0)       # EXIT
1:  j    1b
