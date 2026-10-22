wait: lw x8, 16(x0)
    beq x8, x0, wait
    lw x10, 0(x0)
    lw x11, 4(x0)
    lw x12, 8(x0)
    lw x13, 12(x0)
    add x14, x10, x11
    add x15, x12, x13
    add x31, x14, x15   # 100
    li x30, 1
halt: j halt
