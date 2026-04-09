# Setup
    addi x10, x0, 516       # x10 = 0x204 (Word 1 of the SAME block)
    addi x11, x0, 50        # x11 = Loop 50 times
    addi x12, x0, 1         # x12 = Value to write

    # Offset start slightly so C0 gets the block first
    nop; nop; nop; 

thrash_loop_1:
    beq x11, x0, end
    
    # Write to Word 1.
    # Forces a miss, snoops C0, invalidates C0, enters M.
    sw x12, 0(x10)
    
    addi x12, x12, 1
    addi x11, x11, -1
    jal x0, thrash_loop_1

end:
    nop; nop; nop;
    