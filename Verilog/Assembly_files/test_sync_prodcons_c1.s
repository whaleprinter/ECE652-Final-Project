# Setup
    addi x10, x0, 256       # x10 = 0x100 (Data Address)
    addi x11, x0, 260       # x11 = 0x104 (Flag Address)
    addi x12, x0, 5         # x12 = Loop counter 

consume_loop:
    beq x12, x0, end        # Exit if 5 iterations are done 00060E63

wait_for_producer:
    # 1. Poll Flag waiting for 1. 
    # (Forces a miss, snoops C0, gets dirty block, goes to S)
    lw x14, 0(x11) # 0005A703
    beq x14, x0, wait_for_producer # FE070EE3

    # 2. Read Data (Hit in S)
    lw x15, 0(x10)          # x15 should successively hold 100, 200, 300... // 00052783

    # 3. Write Flag = 0 (S -> M upgrade, Invalidates C0) 
    sw x0, 0(x11)           # 0005A023

    # Prepare next iteration
    addi x12, x12, -1 # FFF60613
    jal x0, consume_loop # FE9FF06F

end:
    nop; nop; nop;
    