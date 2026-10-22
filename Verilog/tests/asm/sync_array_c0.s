# Port of test_sync_array: four words in one block, flag in the next block.
    addi x10, x0, 10
    addi x11, x0, 20
    addi x12, x0, 30
    addi x13, x0, 40
    sw x10, 0(x0)
    sw x11, 4(x0)
    sw x12, 8(x0)
    sw x13, 12(x0)
    addi x8, x0, 1
    sw x8, 16(x0)
    li x31, 0
    li x30, 1
halt: j halt
