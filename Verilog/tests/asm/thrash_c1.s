    addi x10, x0, 516
    addi x11, x0, 50
    addi x12, x0, 1
    nop; nop; nop
loop: beq x11, x0, done
    sw x12, 0(x10)
    addi x12, x12, 1
    addi x11, x11, -1
    j loop
done: li t1, 0x800
    li t2, 1
    sw t2, 0(t1)
    li x31, 0
    li x30, 1
halt: j halt
