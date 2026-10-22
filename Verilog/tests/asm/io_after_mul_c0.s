# A side-effecting I/O load right behind a multiply must happen exactly once.
# (The slot after a mul/div is aborted and replayed; if the aborted copy also
# reached the sync unit, it would claim the lock / bump the counter twice.)
    li s0, 0x80000000
    li a0, 3
    li a1, 5
    li x31, 0
    mul a2, a0, a1
    lw t0, 0x40(s0)     # claim lock 0: must return 0 (acquired)
    beqz t0, 1f
    addi x31, x31, 1
1:  mul a3, a0, a1
    lw t1, 0x60(s0)     # fetch_add counter 0: must return 0
    beqz t1, 2f
    addi x31, x31, 2
2:  lw t2, 0x60(s0)     # now 1
    li t3, 1
    beq t2, t3, 3f
    addi x31, x31, 4
3:  li x30, 1
halt: j halt
