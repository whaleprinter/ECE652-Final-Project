# Port of test_stress_thrash: false sharing on one block.
    addi x10, x0, 512
    addi x11, x0, 50
    addi x12, x0, 1
loop: beq x11, x0, done
    sw x12, 0(x10)
    addi x12, x12, 1
    addi x11, x11, -1
    j loop
done: li t1, 0x800
wait: lw t2, 0(t1)
    beq t2, x0, wait
    lw t3, 0(x10)
    lw t4, 4(x10)
    slli t4, t4, 16
    add x31, t3, t4     # 3276850
    li x30, 1
halt: j halt
