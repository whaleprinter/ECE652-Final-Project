    li a0, 0x200
    li a1, 50
    li a2, 1
loop: beq a1, x0, done
    lw t0, 4(a0)
    sw a2, 4(a0)
    addi a2, a2, 1
    addi a1, a1, -1
    j loop
done: li t1, 0x800
    li t2, 1
    sw t2, 0(t1)
    li x31, 0
    li x30, 1
halt: j halt
