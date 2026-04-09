# Setup
    addi x10, x0, 256       # x10 = 0x100 (Data Address)
    addi x11, x0, 260       # x11 = 0x104 (Flag Address)
    addi x12, x0, 5         # x12 = Loop counter (5 rounds)
    addi x13, x0, 100       # x13 = Initial data payload

produce_loop:
    beq x12, x0, end        # Exit if 5 rounds are done

    # 1. Write Data (I -> M)
    sw x13, 0(x10)          

    # 2. Write Flag = 1 (Hit in M)
    addi x14, x0, 1
    sw x14, 0(x11)          

wait_for_consumer:
    # 3. Poll Flag waiting for 0 (S -> S hits, Arbiter stays quiet)
    lw x14, 0(x11)          
    bne x14, x0, wait_for_consumer 

    # Prepare next round
    addi x13, x13, 100      # Increment payload (200, 300, etc.)
    addi x12, x12, -1       # Decrement loop counter
    jal x0, produce_loop

end:
    nop; nop; nop;
    