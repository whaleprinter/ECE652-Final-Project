# Byte and halfword loads/stores (C uses these for char/short data).
    li s0, 0x600
    li t0, 0x11223344
    sw t0, 0(s0)
    li t1, 0xAA
    sb t1, 1(s0)        # word = 0x1122AA44
    li t1, 0xBEEF
    sh t1, 2(s0)        # word = 0xBEEFAA44
    lw a0, 0(s0)
    li t2, 0xBEEFAA44
    li x31, 0
    beq a0, t2, 1f
    addi x31, x31, 1    # bit 0: store masking wrong
1:  lbu a1, 1(s0)
    li t2, 0xAA
    beq a1, t2, 2f
    addi x31, x31, 2    # lbu wrong
2:  lb a2, 1(s0)
    li t2, -86
    beq a2, t2, 3f
    addi x31, x31, 4    # lb sign extension wrong
3:  lhu a3, 2(s0)
    li t2, 0xBEEF
    beq a3, t2, 4f
    addi x31, x31, 8    # lhu wrong
4:  lh a4, 2(s0)
    li t2, -16657
    beq a4, t2, 5f
    addi x31, x31, 16   # lh wrong
5:  lbu a5, 0(s0)
    li t2, 0x44
    beq a5, t2, 6f
    addi x31, x31, 32   # lbu byte 0 wrong
6:  sb x0, 3(s0)        # word = 0x00EFAA44
    lw a6, 0(s0)
    li t2, 0x00EFAA44
    beq a6, t2, 7f
    addi x31, x31, 64
7:  li s1, 0x700
    sw x0, 0(s1)        # nothing; then evict 0x700's index with a conflicting store
    li s2, 0x1700
    li t1, 0x5A
    sb t1, 2(s2)        # byte store MISS: merged into the block fetched from L2
    lw a7, 0(s2)
    li t2, 0x005A0000
    beq a7, t2, 8f
    addi x31, x31, 128
8:  li x30, 1
halt: j halt
