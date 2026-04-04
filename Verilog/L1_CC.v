module L1_CC (
    // ==========================================
    // CLOCK / RESET
    // ==========================================
    input  wire         clk,
    input  wire         reset,

    // ==========================================
    // CPU INTERFACE (Talks to WARP-V)
    // ==========================================
    input  wire         cpu_req,        // dmem_req_out
    input  wire  [31:0] cpu_addr,       // dmem_addr_out
    input  wire         cpu_we,         // dmem_we_out
    input  wire  [31:0] cpu_wdata,      // dmem_wdata_out
    output wire  [31:0] cpu_rdata,      // dmem_rdata_in
    output reg          cpu_stall,      // dmem_stall_in

    // ==========================================
    // MAIN BUS INTERFACE (Talks to Arbiter/L2)
    // ==========================================
    output reg          bus_req,        // C0_request
    output reg   [31:0] bus_addr,       // C0_address
    output reg          bus_we,         // 0=GetS/GetM read, 1=PutM write/invalidate
    input  wire         bus_grant,      // C0_ready (bus access granted)
    input  wire [127:0] bus_rdata,      // Data returned from L2
    output reg  [127:0] bus_wdata,      // Dirty data being written back
    input  wire         bus_ready,      // Transaction complete (data valid / ack received)

    // ==========================================
    // CORE-TO-CORE LINK (C2C forwarding)
    // ==========================================
    output reg          link_push_req,  // Push dirty data to requesting core
    output reg  [127:0] link_data_out,  // Data being forwarded
    input  wire         link_push_valid,// Incoming C2C data is valid this cycle
    input  wire [127:0] link_data_in,   // Incoming C2C forwarded data

    // ==========================================
    // SNOOP INTERFACE (From Arbiter)
    // ==========================================
    input  wire         snoop_req,      // C0_check_L1
    input  wire  [31:0] snoop_addr,     // C0_L1_address
    input  wire         snoop_type,     // 0=GetS (read), 1=GetM (write/invalidate)
    output reg          snoop_hit,      // C0_L1_hit
    output reg          snoop_dirty     // C0_L1_dirty
);

    // ==========================================
    // MSI STATE ENCODING
    // ==========================================
    localparam I    = 3'd0;  // Invalid
    localparam S    = 3'd1;  // Shared (clean, read-only)
    localparam M    = 3'd2;  // Modified (dirty, exclusive)
    // Transient states (waiting for bus response)
    localparam IS_D = 3'd3;  // Invalid → Shared, waiting for data
    localparam IM_D = 3'd4;  // Invalid → Modified, waiting for data/ack
    localparam SM_D = 3'd5;  // Shared  → Modified, waiting for upgrade ack

    // ==========================================
    // CACHE TAG & STATE ARRAYS  (256 lines)
    // ==========================================
    reg [19:0] tags   [0:255];
    reg  [2:0] states [0:255];

    // ==========================================
    // ADDRESS DECOMPOSITION
    // cpu_addr / snoop_addr layout:
    //   [31:12] tag  (20 bits)
    //   [11:4]  index (8 bits)
    //   [3:2]   word offset (2 bits)
    //   [1:0]   byte offset (ignored)
    // ==========================================
    wire [19:0] req_tag    = cpu_addr[31:12];
    wire  [7:0] req_index  = cpu_addr[11:4];
    wire  [1:0] req_offset = cpu_addr[3:2];

    wire [19:0] snp_tag   = snoop_addr[31:12];
    wire  [7:0] snp_index = snoop_addr[11:4];

    // ==========================================
    // CACHE DATA ARRAY INTERFACE
    // active_index: mux between CPU and snoop so
    // dcache combinatorially presents the right
    // line for both CPU hits and snoop dirty reads.
    // ==========================================
    wire [7:0] active_index = snoop_req ? snp_index : req_index;

    reg          dcache_ctrl_we;
    reg  [127:0] dcache_ctrl_wdata;
    wire [127:0] dcache_ctrl_rdata;

    // Word write enable: only write CPU data when there is a genuine
    // write hit (M state, tag match) and no stall is being generated.
    wire dcache_cpu_we = cpu_req & cpu_we & ~cpu_stall;

    L1D_cache dcache (
        .clk             (clk),
        .index           (active_index),
        .offset          (req_offset),
        .word_write_enable (dcache_cpu_we),
        .word_write_data   (cpu_wdata),
        .word_read_data    (cpu_rdata),
        .ctrl_write_enable (dcache_ctrl_we),
        .ctrl_write_data   (dcache_ctrl_wdata),
        .ctrl_read_data    (dcache_ctrl_rdata)
    );

    // ==========================================
    // HIT DETECTION  (combinatorial)
    // ==========================================
    wire tag_match = (tags[req_index] == req_tag);
    wire hit       = tag_match && (states[req_index] != I);

    // ==========================================
    // CONTEXT REGISTERS  (saved across stall)
    // ==========================================
    // Need to save the CPU's original request address and write enable so that we can re-issue the correct bus request after evicting a dirty block 
    reg        saved_cpu_we;
    reg [31:0] saved_cpu_addr;

    // Tracks whether the outstanding bus request is a dirty eviction
    // (PutM) rather than a demand fetch/upgrade.  When bus_ready fires
    // while evict_active=1 the controller issues the real fetch/upgrade.
    reg evict_active;

    // ==========================================
    // MAIN FSM
    // ==========================================
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 256; i = i + 1) begin
                tags[i]   <= 20'b0;
                states[i] <= I;
            end
            cpu_stall      <= 0;
            bus_req        <= 0;
            bus_addr       <= 0;
            bus_we         <= 0;
            bus_wdata      <= 128'b0;
            link_push_req  <= 0;
            link_data_out  <= 128'b0;
            snoop_hit      <= 0;
            snoop_dirty    <= 0;
            dcache_ctrl_we    <= 0;
            dcache_ctrl_wdata <= 128'b0;
            evict_active   <= 0;
            saved_cpu_we   <= 0;
            saved_cpu_addr <= 0;
        end else begin

            // ----------------------------------------------------------
            // DEFAULT PULSE SIGNALS (de-assert every cycle unless set)
            // ----------------------------------------------------------
            dcache_ctrl_we <= 0;
            link_push_req  <= 0;
            snoop_hit      <= 0;
            snoop_dirty    <= 0;

            // Snooping logic. 
            if (snoop_req) begin
                if (tags[snp_index] == snp_tag && states[snp_index] != I) begin
                    snoop_hit <= 1;

                    case (states[snp_index])

                        M: begin
                            // dirty block so send data to requesting core via the link.
                            snoop_dirty   <= 1;
                            link_push_req <= 1;
                            link_data_out <= dcache_ctrl_rdata;

                            if (snoop_type == 1) begin
                                // GetM: another core wants exclusive ownership
                                // M → I  (we lose the line entirely)
                                states[snp_index] <= I;
                            end else begin
                                // GetS: another core wants a read copy
                                // M → S  (we keep a clean shared copy)
                                states[snp_index] <= S;
                            end
                        end

                        S: begin
                            // Shared lines are always clean
                            snoop_dirty <= 0;
                            if (snoop_type == 1) begin
                                // GetM: another core needs exclusive access
                                // S → I  (invalidate our copy)
                                states[snp_index] <= I;
                            end
                            // GetS on S: no state change needed
                        end

                        // Transient states: a transaction is already in
                        // flight for this line.  For a minimal correct
                        // implementation we treat these as a miss to the
                        // snooper (the line is not yet usable).
                        // A full implementation would NACK and retry.
                        // TODO: IMPLEMENT NACKS
                        IS_D, IM_D, SM_D: begin
                            snoop_hit   <= 0;
                            snoop_dirty <= 0;
                        end

                        default: begin
                            snoop_hit   <= 0;
                            snoop_dirty <= 0;
                        end
                    endcase
                end
                // else: tag miss — snoop_hit/dirty remain 0 (defaults above)
            end

            // ===========================================================
            // BLOCK 2: BUS GRANT / RESPONSE HANDLING
            // Runs independently of whether a snoop arrived this cycle.
            // ===========================================================

            // De-assert bus_req once the arbiter grants access.
            if (bus_grant)
                bus_req <= 0;

            if (bus_ready) begin
                if (evict_active) begin
                    // If core tries to write to a block that is in M but has tag mismatch, must first evict the dirty block before issuing the real request for the new blcok. 
                    // -------------------------------------------------------
                    // The dirty eviction (PutM) has been acknowledged.
                    // Now issue the real demand request for the new address.
                    // -------------------------------------------------------
                    evict_active <= 0;
                    bus_req  <= 1;
                    bus_we   <= saved_cpu_we ? 1'b1 : 1'b0;
                    bus_addr <= saved_cpu_addr;

                    if (saved_cpu_we)
                        states[saved_cpu_addr[11:4]] <= IM_D;
                    else
                        states[saved_cpu_addr[11:4]] <= IS_D;

                end else begin
                    // -------------------------------------------------------
                    // Demand fetch or upgrade has completed.
                    // Fill the cache line and wake the CPU.
                    // -------------------------------------------------------
                    dcache_ctrl_we    <= 1;
                    // Prefer C2C-forwarded data if available this cycle
                    dcache_ctrl_wdata <= link_push_valid ? link_data_in : bus_rdata;

                    tags[saved_cpu_addr[11:4]] <= saved_cpu_addr[31:12];
                    if (bus_ready && !evict_active) begin // DEBUG
                        $display("FILL: saved=%0h index=%0h tag=%0h",saved_cpu_addr, saved_cpu_addr[11:4], saved_cpu_addr[31:12]);
                    end
                    cpu_stall <= 0;

                    // Resolve transient state → stable state
                    case (states[saved_cpu_addr[11:4]])
                        IS_D:         states[saved_cpu_addr[11:4]] <= S;
                        IM_D, SM_D:   states[saved_cpu_addr[11:4]] <= M;
                        default: ;    // Should not occur; leave state unchanged
                    endcase
                end
            end

            // ===========================================================
            // BLOCK 3: CPU REQUEST HANDLING
            // Only look at new CPU requests when not already stalled
            // (stall means we are waiting for an outstanding bus transaction).
            // ===========================================================
            else if (cpu_req && !cpu_stall) begin

                case (states[req_index])

                    
                    I: begin
                        cpu_stall      <= 1;
                        saved_cpu_we   <= cpu_we;
                        saved_cpu_addr <= cpu_addr;
                        bus_req        <= 1;
                        bus_addr       <= cpu_addr;
                        if (cpu_we) begin
                            bus_we             <= 1;     // GetM
                            states[req_index]  <= IM_D;
                        end else begin
                            bus_we             <= 0;     // GetS
                            states[req_index]  <= IS_D;
                        end
                    end

                    
                    S: begin
                        if (!tag_match) begin
                            // Clean eviction 
                            // No write back
                            states[req_index]  <= I;
                            cpu_stall          <= 1;
                            saved_cpu_we       <= cpu_we;
                            saved_cpu_addr     <= cpu_addr;
                            bus_req            <= 1;
                            bus_addr           <= cpu_addr;
                            if (cpu_we) begin
                                bus_we            <= 1;
                                states[req_index] <= IM_D;
                            end else begin
                                bus_we            <= 0;
                                states[req_index] <= IS_D;
                            end
                        end else begin
                            // Tag match in S
                            if (cpu_we) begin
                                // Write hit in S so upgrade to M
                                cpu_stall          <= 1;
                                saved_cpu_we       <= cpu_we;
                                saved_cpu_addr     <= cpu_addr;
                                bus_req            <= 1;
                                bus_we             <= 1;   // GetM upgrade
                                bus_addr           <= cpu_addr;
                                states[req_index]  <= SM_D;
                            end
                            // else: read hit in S 
                        end
                    end

                    M: begin
                        if (!tag_match) begin
                            // Dirty eviction required before fetching new line
                            cpu_stall      <= 1;
                            saved_cpu_we   <= cpu_we;
                            saved_cpu_addr <= cpu_addr;
                            evict_active   <= 1;
                            bus_req        <= 1;
                            bus_we         <= 1;   // PutM writeback
                            // Reconstruct the full address of the dirty line
                            bus_addr       <= {tags[req_index], req_index, 4'b0};
                            bus_wdata      <= dcache_ctrl_rdata;
                        end
                        // else: tag match in M → read or write hit, no stall
                    end

                    IS_D, IM_D, SM_D: begin

                    end

                    default: ;

                endcase
            end

        end // !reset
    end // always

endmodule



