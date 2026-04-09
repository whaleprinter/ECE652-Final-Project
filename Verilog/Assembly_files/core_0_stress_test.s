# Setup
    addi x10, x0, 256      # x10 = Base Address (0x100)
    addi x11, x0, 42       # x11 = Data to write (0x2A)

    # =================================================================
    # PHASE 1: Write Miss (I -> M)
    # =================================================================
    # Core 0 writes to 0x100. It should miss, fetch 0s from L2, merge 
    # the 42, and enter the 'M' state.
    sw x11, 0(x10)         
    
    nop; nop; 

    # =================================================================
    # PHASE 2: The Dirty Intervention (M -> S)
    # =================================================================
    # Core 1 is currently reading 0x100. 
    # EXPECT IN WAVEFORM: Core 0 receives snoop_req, asserts snoop_dirty,
    # asserts link_push_req, pushes data, and downgrades to 'S'.
    nop; nop; 

    # =================================================================
    # PHASE 3: Shared Read Hit (S -> S)
    # =================================================================
    # Core 0 reads 0x100. 
    # EXPECT IN WAVEFORM: Instant 0-cycle cache hit. No bus traffic.
    # Register x12 should get 42.
    lw x12, 0(x10)         

    nop; nop; 

    # =================================================================
    # PHASE 4: The Invalidation (S -> I)
    # =================================================================
    # Core 1 is currently writing to 0x100 to upgrade to 'M'.
    # EXPECT IN WAVEFORM: Core 0 receives snoop_type=1 (GetM).
    # Core 0 must transition its cache block from 'S' to 'I'.
    nop; nop; 
    # =================================================================
    # PHASE 5: Read Miss on Invalidated Line (I -> S)
    # =================================================================
    # Core 0 reads 0x100 again.
    # EXPECT IN WAVEFORM: Since Core 0 was invalidated, it misses. 
    # It must snoop Core 1, catch Core 1's dirty data, and go to 'S'.
    # Register x13 should get 99.
    lw x13, 0(x10)
    
    nop; nop; nop; nop; nop;
    