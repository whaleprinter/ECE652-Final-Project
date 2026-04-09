# Setup
    li x13, 16384     # x13 = Flag address (0x4000)
    li x10, 4096      # x10 = 0x1000 (The address C0 was forced to evict)

wait_for_eviction:
    lw x14, 0(x13)
    beq x14, x0, wait_for_eviction

    # C0 has finished overflowing its cache. Address 0x1000 is no longer in C0's L1.
    # It should have been written back to L2 via a PutM.
    # EXPECT: Arbiter goes to L2, NOT a dirty snoop from C0.
    # x15 should successfully load the value '1'.
    lw x15, 0(x10)

end:
    nop; nop; nop;
