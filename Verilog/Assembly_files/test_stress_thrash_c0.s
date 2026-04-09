# Setup
    addi x10, x0, 512       # x10 = 0x200 (Word 0 of the block)
    addi x11, x0, 50        # x11 = Loop 50 times
    addi x12, x0, 1         # x12 = Value to write

thrash_loop_0:
    beq x11, x0, end
    
    # Write to Word 0. 
    # If C1 just wrote, this forces a miss, snoops C1, invalidates C1, enters M.
    sw x12, 0(x10)
    
    addi x12, x12, 1
    addi x11, x11, -1
    jal x0, thrash_loop_0

end:
    nop; nop; nop;
    