# Port of test_mem_evict: 257 dirty blocks overflow the 256-block L1D.
    li x10, 4096
    addi x11, x0, 257
    addi x12, x0, 1
loop: beq x11, x0, notify
    sw x12, 0(x10)
    addi x12, x12, 1
    addi x10, x10, 16
    addi x11, x11, -1
    j loop
notify: li x13, 0x3800
    addi x14, x0, 1
    sw x14, 0(x13)
    li x31, 0
    li x30, 1
halt: j halt
