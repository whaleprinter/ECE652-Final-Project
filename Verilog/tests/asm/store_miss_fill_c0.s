# A store miss must read the rest of the block from L2 (GetM is a read, not a write).
    li t0, 0x1004
    li t1, 11
    sw t1, 0(t0)        # block 0x1000 -> M (index 0)
    li t0, 0x2000
    li t1, 22
    sw t1, 0(t0)        # conflict: write back 0x1000, then GetM 0x2000
    li t0, 0x1000
    li t1, 33
    sw t1, 0(t0)        # conflict: write back 0x2000, then GetM 0x1000 (store miss)
    lw t2, 4(t0)        # expect 11 (from L2)
    lw t3, 0(t0)        # expect 33
    slli t2, t2, 8
    add x31, t2, t3     # 11*256 + 33 = 2849
    li x30, 1
halt: j halt
