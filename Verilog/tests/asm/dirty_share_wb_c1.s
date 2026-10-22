    li a1, 0x800
wait: lw t0, 0(a1)
    beq t0, x0, wait
    li a0, 0x100
    lw t1, 0(a0)        # GetS: C0 forwards over the link, M -> S
    li a3, 0x1100
    lw t2, 0(a3)        # evict 0x100 (clean, S) from C1
    li a2, 0x900
    li t0, 1
    sw t0, 0(a2)
    mv x31, t1          # expect 85
    li x30, 1
halt: j halt
