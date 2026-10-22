    li x13, 0x3800
wait: lw x14, 0(x13)
    beq x14, x0, wait
    li x10, 4096
    lw t0, 0(x10)       # 1   (evicted to L2 by the 257th store)
    lw t1, 16(x10)      # 2   (still M in C0: forwarded over the link)
    li x11, 0x2000
    lw t2, 0(x11)       # 257
    add x31, t0, t1
    add x31, x31, t2    # 260
    li x30, 1
halt: j halt
