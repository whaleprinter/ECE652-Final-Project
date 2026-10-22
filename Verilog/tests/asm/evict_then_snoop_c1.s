    li a0, 0x2000
    li t0, 77
    sw t0, 0(a0)        # 0x2000 -> M in C1
    li a1, 0x800
    li t0, 1
    sw t0, 0(a1)
    li x31, 0
    li x30, 1
halt: j halt
