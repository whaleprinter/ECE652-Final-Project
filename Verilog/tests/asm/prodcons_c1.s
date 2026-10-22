    addi x10, x0, 256
    addi x11, x0, 260
    addi x12, x0, 5
    li x31, 0
consume: beq x12, x0, done
waitp: lw x14, 0(x11)
    beq x14, x0, waitp
    lw x15, 0(x10)
    add x31, x31, x15   # 100+200+300+400+500 = 1500
    sw x0, 0(x11)
    addi x12, x12, -1
    j consume
done: li x30, 1
halt: j halt
