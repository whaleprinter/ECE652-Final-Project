# Setup
    addi x10, x0, 256      # x10 = Base Address (0x100)
    addi x11, x0, 99       # x11 = Data to write later (0x63)

    # =================================================================
    # PHASE 1: Wait for Core 0
    # =================================================================
    # Let Core 0 finish its initial Write Miss.
    nop; nop; 

    # =================================================================
    # PHASE 2: The Catch (I -> S)
    # =================================================================
    # Core 1 reads 0x100. 
    # EXPECT IN WAVEFORM: Core 1 misses, Arbiter snoops Core 0. 
    # Core 1 catches the 42 via link_data_in, enters 'S' state.
    # Register x12 should get 42.
    lw x12, 0(x10)

    nop; nop; 

    # =================================================================
    # PHASE 3: Wait for Core 0's Hit
    # =================================================================
    # Let Core 0 do its Shared Read Hit in peace.
    nop; nop; 

    # =================================================================
    # PHASE 4: The Upgrade / Invalidate (S -> M)
    # =================================================================
    # Core 1 writes to 0x100.
    # EXPECT IN WAVEFORM: Core 1 hits in 'S', but needs 'M'. It issues a 
    # bus request (GetM) to invalidate Core 0. Once bus_ready pulses, 
    # it writes 99 into the cache and enters 'M' state.
    sw x11, 0(x10)

    nop; nop; 
    # =================================================================
    # PHASE 5: The Reverse Intervention (M -> S)
    # =================================================================
    # Core 0 is currently reading.
    # EXPECT IN WAVEFORM: Core 1 receives snoop_req, pushes its dirty '99'
    # across the link to Core 0, and downgrades to 'S'.
    nop; nop; 
    