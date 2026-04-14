# Setup
    li x10, 4096      # x10 = 0x1000 (Start address)
    addi x11, x0, 257       # x11 = Write 257 blocks (overflows 256-block cache)
    addi x12, x0, 1         # x12 = Counter 

evict_loop:
    beq x11, x0, notify_c1
    
    # Write value to the first word of the block
    sw x12, 0(x10)
    
    addi x12, x12, 1
    addi x10, x10, 16       # Step 16 bytes (exactly 1 cache block index)
    addi x11, x11, -1
    jal x0, evict_loop

notify_c1:
    # Tell C1 we are done by writing to a dedicated flag at 0x4000
    li x13, 16384     # 0x4000
    addi x14, x0, 1
    sw x14, 0(x13)
    
end:
    nop; nop; nop;
