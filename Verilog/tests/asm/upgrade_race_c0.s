# Both cores read then write different words of one block, so S->M upgrades race.
# A core in SM_D that loses arbitration must drop its stale copy (SM_D + Other-GetM -> IM_D).
    li a0, 0x200
    li a1, 50
    li a2, 1
loop: beq a1, x0, done
    lw t0, 0(a0)
    sw a2, 0(a0)
    addi a2, a2, 1
    addi a1, a1, -1
    j loop
done: li t1, 0x800
wait: lw t2, 0(t1)
    beq t2, x0, wait
    lw t3, 0(a0)        # expect 50
    lw t4, 4(a0)        # expect 50
    slli t4, t4, 16
    add x31, t3, t4     # 50 + 50<<16 = 3276850
    li x30, 1
halt: j halt
