# Port of test_sync_prodcons: data and flag share one block.
    addi x10, x0, 256
    addi x11, x0, 260
    addi x12, x0, 5
    addi x13, x0, 100
produce: beq x12, x0, done
    sw x13, 0(x10)
    addi x14, x0, 1
    sw x14, 0(x11)
waitc: lw x14, 0(x11)
    bne x14, x0, waitc
    addi x13, x13, 100
    addi x12, x12, -1
    j produce
done: li x31, 0
    li x30, 1
halt: j halt
