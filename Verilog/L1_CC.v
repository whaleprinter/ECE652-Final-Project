 module L1_CC (

    input  wire         clk,
    input  wire         reset,

    // Core                             // ROSHAN THESE ARE THE WIRE NAMES!!!!!
    input  wire         cpu_req,        // dmem_req_out
    input  wire  [31:0] cpu_addr,       // dmem_addr_out
    input  wire         cpu_we,         // dmem_we_out
    input  wire  [31:0] cpu_wdata,      // dmem_wdata_out
    output wire  [31:0] cpu_rdata,      // dmem_rdata_in
    output wire          cpu_stall,      // dmem_stall_in

    // Arbiter
    output reg          bus_req,        // C0_request
    output reg   [31:0] bus_addr,       // C0_address
    output reg          bus_we,         // 0=GetS/GetM read, 1=PutM write/invalidate
    input  wire         bus_grant,      // C0_ready (bus access granted)
    input  wire [127:0] bus_rdata,      // Data returned from L2
    output reg  [127:0] bus_wdata,      // Dirty data being written back
    input  wire         bus_ready,      // Transaction complete (data valid / ack received)

    // Core to core transfers
    output reg          link_push_req,  // Push dirty data to requesting core
    output wire  [127:0] link_data_out,  // Data being forwarded
    input  wire         link_push_valid,// Incoming C2C data is valid this cycle
    input  wire [127:0] link_data_in,   // Incoming C2C forwarded data

    // Snooping
    input  wire         snoop_req,      // C0_check_L1
    input  wire  [31:0] snoop_addr,     // C0_L1_address
    input  wire         snoop_type,     // 0=GetS (read), 1=GetM (write/invalidate)
    output wire          snoop_hit,      // C0_L1_hit
    output wire          snoop_dirty     // C0_L1_dirty
);

    
    localparam I    = 3'd0; 
    localparam S    = 3'd1; 
    localparam M    = 3'd2; 
    localparam IS_D = 3'd3; 
    localparam IM_D = 3'd4; 
    localparam SM_D = 3'd5; 

    reg [19:0] tags   [0:255];
    reg  [2:0] states [0:255];
    
    integer j;
    initial begin
        for (j = 0; j < 256; j = j + 1) begin
            states[j] = 2'b00; 
            tags[j]   = 24'b0;
        end
    end

    //   [31:12] tag 
    //   [11:4]  index 
    //   [3:2]   word offset
    //   [1:0]   byte offset 

    // wire [19:0] req_tag    = cpu_addr[31:12];
    // wire  [7:0] req_index  = cpu_addr[11:4];
    // wire  [1:0] req_offset = cpu_addr[3:2];

    wire [19:0] snp_tag   = snoop_addr[31:12];
    wire  [7:0] snp_index = snoop_addr[11:4];

    // wire [7:0] active_index = snoop_req ? snp_index : req_index;
    // Hold the snoop index steady while we are pushing data across the link!
    wire [7:0] active_index = (snoop_req || link_push_req) ? snp_index : req_index;

    reg          dcache_ctrl_we;
    reg  [127:0] dcache_ctrl_wdata;
    wire [127:0] dcache_ctrl_rdata;

    // BEGIN NEW


    // ==========================================
    // 1. SNAPSHOT BUFFER (The Request Latch)
    // ==========================================
    reg        hold_req;
    reg [31:0] hold_addr;
    reg        hold_we;
    reg [31:0] hold_wdata;

    // Detect if the Arbiter is handing us data this exact cycle
    wire data_just_arrived = (bus_ready && !evict_active);
    wire fill_match        = data_just_arrived && (hold_addr[31:4] == cpu_addr[31:4]);

    always @(posedge clk) begin
        if (reset) begin
            hold_req <= 0;
        end else if (cpu_req && cpu_stall && !hold_req) begin
            // Lock the vault on a miss
            hold_req   <= 1;
            hold_addr  <= cpu_addr;
            hold_we    <= cpu_we;
            hold_wdata <= cpu_wdata;
        end else if (fill_match) begin // Revert to else if fill_match
            // Unlock the vault when data arrives
            hold_req <= 0;
        end
    end

    // Use these wires for ALL cache logic below this point!
    wire        eff_cpu_req   = hold_req ? 1'b1       : cpu_req;
    wire [31:0] eff_cpu_addr  = hold_req ? hold_addr  : cpu_addr;
    wire        eff_cpu_we    = hold_req ? hold_we    : cpu_we;
    wire [31:0] eff_cpu_wdata = hold_req ? hold_wdata : cpu_wdata;

    // ==========================================
    // 2. MEALY BUS REQUEST (No 1-Cycle Delay)
    // ==========================================
    // assign bus_req = (eff_cpu_req && cache_needs_stall) || evict_active;


    // END NEW

    wire [19:0] req_tag    = eff_cpu_addr[31:12];
    wire  [7:0] req_index  = eff_cpu_addr[11:4];
    wire  [1:0] req_offset = eff_cpu_addr[3:2];

    // Word write enable: only write CPU data when needed
    wire dcache_cpu_we = cpu_req & cpu_we & ~cpu_stall;

    wire [7:0] ctrl_index = (snoop_req || link_push_req) ? snp_index : saved_cpu_addr[11:4];

    L1D_cache dcache (
        .clk             (clk),
        .cpu_index       (active_index),
        .offset          (req_offset),
        .word_write_enable (dcache_cpu_we),
        .word_write_data   (eff_cpu_wdata),
        .word_read_data    (cpu_rdata),

        .ctrl_index        (ctrl_index),
        .ctrl_write_enable (dcache_ctrl_we),
        .ctrl_write_data   (dcache_ctrl_wdata),
        .ctrl_read_data    (dcache_ctrl_rdata)
    );

    // Detect cache hit
    wire tag_match = (tags[req_index] == req_tag);
    wire hit       = tag_match && (states[req_index] != I);

    // ==========================================
    // 4. COMBINATORIAL SNOOP RESPONSES
    // ==========================================
    wire is_snoop_match = (tags[snp_index] == snp_tag) && (states[snp_index] != I);
    
    // Instantly answer the Arbiter
    assign snoop_hit   = snoop_req && is_snoop_match;
    assign snoop_dirty = snoop_req && is_snoop_match && (states[snp_index] == M);
    // Instantly forward whatever the SRAM is currently reading
    assign link_data_out = dcache_ctrl_rdata;


    // Need to save the CPU's original request address and write enable so that we can re-issue the correct bus request after evicting a dirty block 
    reg        saved_cpu_we;
    reg [31:0] saved_cpu_addr;

    // Tracks whether the outstanding bus request is a dirty eviction
    reg evict_active;


    // wire is_stable = (states[req_index] == I || states[req_index] == S || states[req_index] == M);

    // BEGIN NEW

    // ==========================================
    // 3. STALL LOGIC & DATA BYPASS
    // ==========================================
    wire is_stable = (states[req_index] == I || states[req_index] == S || states[req_index] == M);

    wire cache_needs_stall = (
        (states[req_index] == I) || 
        (states[req_index] == S && eff_cpu_we) || 
        (!tag_match && states[req_index] != I) || 
        (!is_stable)
    );

    // Freeze CPU instantly, but drop the stall the exact cycle fill_match is true
    // assign cpu_stall = eff_cpu_req && cache_needs_stall && !fill_match;
    // ==========================================
    // 3. STALL LOGIC (10-Cycle Fixed Timer)
    // ==========================================
                    // reg [3:0] stall_counter;

                    // // The 10-Cycle Countdown Timer
                    // always @(posedge clk) begin
                    //     if (reset) begin
                    //         stall_counter <= 4'd0;
                    //     end else begin
                    //         // Cycle 0: A miss is detected. Start the timer at 10.
                    //         if (eff_cpu_req && cache_needs_stall && stall_counter == 0) begin
                    //             stall_counter <= 4'd10; 
                    //         end 
                    //         // Cycle 1-10: Count down to zero.
                    //         else if (stall_counter > 0) begin
                    //             stall_counter <= stall_counter - 4'd1; 
                    //         end
                    //     end
                    // end

                    // // STALL ASSERTION:
                    // // Freeze instantly on Cycle 0 (combinatorial), and keep it frozen while counting > 0.
                    // // The exact moment stall_counter hits 0, this drops to 0, and the CPU wakes up.
                    // assign cpu_stall = (eff_cpu_req && cache_needs_stall && stall_counter == 0) || (stall_counter > 0);
    // ==========================================
    // 3. STALL LOGIC & DATA BYPASS
    // ==========================================
    // FREEZE OVERRIDE: 
    // Freeze instantly on a miss.
    // Drop the stall on the exact cycle the Arbiter returns the data (!fill_match).
    assign cpu_stall = eff_cpu_req && cache_needs_stall && !fill_match;
    // Route incoming Arbiter/Snoop data directly to the CPU if it's arriving right now
    wire [127:0] incoming_line = link_push_valid ? link_data_in : bus_rdata;
    reg [31:0] incoming_word;
    always @(*) begin
        case (req_offset)
            2'b00: incoming_word = incoming_line[31:0];
            2'b01: incoming_word = incoming_line[63:32];
            2'b10: incoming_word = incoming_line[95:64];
            2'b11: incoming_word = incoming_line[127:96];
        endcase
    end

    // sram_word_read_data is the wire coming OUT of your L1D_cache module
    assign cpu_rdata = fill_match ? incoming_word : dcache_ctrl_rdata;

    // END NEW

    // // Freeze CPU instantly if it makes a request and the cache is not ready
    // assign cpu_stall = cpu_req && (
    //     (states[req_index] == I) || 
    //     (states[req_index] == S && cpu_we) || 
    //     (!tag_match && states[req_index] != I) || 
    //     (!is_stable)
    // );

    

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 256; i = i + 1) begin
                tags[i]   <= 20'b0;
                states[i] <= I;
            end
            // cpu_stall      <= 0;
            bus_req        <= 0;
            bus_addr       <= 0;
            bus_we         <= 0;
            bus_wdata      <= 128'b0;
            link_push_req  <= 0;
            // link_data_out  <= 128'b0;
            // snoop_hit      <= 0;
            // snoop_dirty    <= 0;
            dcache_ctrl_we    <= 0;
            dcache_ctrl_wdata <= 128'b0;
            evict_active   <= 0;
            saved_cpu_we   <= 0;
            saved_cpu_addr <= 0;
        end else begin

           
            dcache_ctrl_we <= 0;
            link_push_req  <= 0;
            // snoop_hit      <= 0;
            // snoop_dirty    <= 0;

            if (snoop_req) begin
                if (tags[snp_index] == snp_tag && states[snp_index] != I) begin
                    // snoop_hit <= 1;

                    case (states[snp_index])

                        M: begin
                            // dirty block so send data to requesting core via the link.
                            // snoop_dirty   <= 1;
                            link_push_req <= 1;
                            // link_data_out <= dcache_ctrl_rdata;

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
                            // snoop_dirty <= 0;
                            if (snoop_type == 1) begin
                                // GetM --> S → I  
                                states[snp_index] <= I;
                            end
                            // GetS on S: no state change needed
                        end

                        // TODO: IMPLEMENT NACKS
                        IS_D, IM_D, SM_D: begin
                            // snoop_hit   <= 0;
                            // snoop_dirty <= 0;
                        end

                        default: begin
                            // snoop_hit   <= 0;
                            // snoop_dirty <= 0;
                        end
                    endcase
                end
            end

            // Response

            if (bus_grant) begin
                bus_req <= 0;
            end 
            if (bus_ready) begin
                if (evict_active) begin
                    // PutM acknowledged, so now issue original request for the block
                    evict_active <= 0;
                    bus_req  <= 1;
                    bus_we   <= saved_cpu_we ? 1'b1 : 1'b0;
                    bus_addr <= saved_cpu_addr;

                    if (saved_cpu_we)
                        states[saved_cpu_addr[11:4]] <= IM_D;
                    else
                        states[saved_cpu_addr[11:4]] <= IS_D;

                end else begin
                    
                    dcache_ctrl_we    <= 1;

                    dcache_ctrl_wdata <= link_push_valid ? link_data_in : bus_rdata; // Get data from L2 or another core 

                    tags[saved_cpu_addr[11:4]] <= saved_cpu_addr[31:12];
                    // if (bus_ready && !evict_active) begin // DEBUG
                    //     $display("FILL: saved=%0h index=%0h tag=%0h",saved_cpu_addr, saved_cpu_addr[11:4], saved_cpu_addr[31:12]);
                    // end
                    // cpu_stall <= 0;

                    // Resolve transient states
                    case (states[saved_cpu_addr[11:4]])
                        IS_D:         states[saved_cpu_addr[11:4]] <= S;
                        IM_D, SM_D:   states[saved_cpu_addr[11:4]] <= M;
                        default: ;  
                    endcase
                end
            end

            // CPU Request Handling
            else if (cpu_req && is_stable) begin // cpu_req && !cpu_stall is the old condition

                case (states[req_index])

                    
                    I: begin
                        // cpu_stall      <= 1;
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
                            // cpu_stall          <= 1;
                            saved_cpu_we       <= cpu_we;
                            saved_cpu_addr     <= cpu_addr;
                            // bus_req            <= 1;
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
                                // cpu_stall          <= 1;
                                saved_cpu_we       <= cpu_we;
                                saved_cpu_addr     <= cpu_addr;
                                // bus_req            <= 1;
                                bus_we             <= 1;   // GetM 
                                bus_addr           <= cpu_addr;
                                states[req_index]  <= SM_D;
                            end
                        end
                    end

                    M: begin
                        if (!tag_match) begin
                            // Dirty eviction required before fetching new line
                            // cpu_stall      <= 1;
                            saved_cpu_we   <= cpu_we;
                            saved_cpu_addr <= cpu_addr;
                            evict_active   <= 1;
                            // bus_req        <= 1;
                            bus_we         <= 1;   // PutM writeback
                            bus_addr       <= {tags[req_index], req_index, 4'b0};
                            bus_wdata      <= dcache_ctrl_rdata;
                        end
                    end

                    IS_D, IM_D, SM_D: begin

                    end

                    default: ;

                endcase
            end

        end 
    end 

 endmodule



