# After a dirty eviction, the re-issued request must snoop the NEW address.
    li a0, 0x1000
    li t0, 5
    sw t0, 0(a0)        # 0x1000 -> M (index 0)
    li a1, 0x800
wait: lw t1, 0(a1)
    beq t1, x0, wait
    li a2, 0x2000
    lw x31, 0(a2)       # evict 0x1000, then GetS 0x2000 (M in C1): expect 77
    li x30, 1
halt: j halt
