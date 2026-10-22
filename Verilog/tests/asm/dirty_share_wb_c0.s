# M -> S on a remote GetS must update L2, or the data is lost once both copies are evicted.
    li a0, 0x100
    li t0, 85
    sw t0, 0(a0)        # 0x100 -> M in C0
    li a1, 0x800
    li t0, 1
    sw t0, 0(a1)        # tell C1 to read 0x100
    li a2, 0x900
wait: lw t1, 0(a2)
    beq t1, x0, wait    # wait for C1 to finish
    li a3, 0x1100
    lw t2, 0(a3)        # evict 0x100 (clean, S) from C0
    lw x31, 0(a0)       # re-fetch from L2: expect 85
    li x30, 1
halt: j halt
