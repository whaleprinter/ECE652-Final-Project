# A multiply/divide result must survive a data-cache miss right behind it
# (the core writes long-latency results back while the L1 may be stalling it).
    li a0, 7
    li a1, 6
    li s0, 0x1000
    li s1, 0x2000
    li t0, 100
    sw t0, 0(s1)        # 0x2000 -> M (index 0)
    mul a2, a0, a1      # 42
    lw t1, 0(s0)        # miss + dirty eviction right behind the mul
    add x31, a2, t1     # 42 + 0
    li a3, 1000
    li a4, 7
    divu a5, a3, a4     # 142
    lw t2, 0(s1)        # miss again (0x2000 was evicted)
    add a5, a5, t2      # 142 + 100
    add x31, x31, a5    # 42 + 242 = 284
    mul a6, a0, a0      # 49
    sw a6, 16(s0)       # store miss right behind the mul
    lw t3, 16(s0)
    add x31, x31, t3    # 284 + 49 = 333
    li x30, 1
halt: j halt
