module L1_CC(
    // ==========================================
    // CPU INTERFACE (Talks to WARP-V)
    // ==========================================
    input  wire         cpu_req, // 
    input  wire  [31:0] cpu_addr, // dmem_addr_out 
    input  wire         cpu_we,  // dmem_we_out
    input  wire  [31:0] cpu_wdata, // dmem_wdata_out
    output wire  [31:0] cpu_rdata, // dmem_rdata_in
    output reg          cpu_stall, // dmem_stall_in

    // ==========================================
    // MAIN BUS INTERFACE (Talks to Arbiter/L2)
    // ==========================================
    output reg          bus_req, // C0_request
    output reg   [31:0] bus_addr, // C0_address
    output reg          bus_we,       // 0 = Read, 1 = Write/Invalidate // C0_write_enable
    input  wire         bus_grant,  // C0_ready
    input  wire [127:0] bus_rdata,  // For L2 // 
    output reg  [127:0] bus_wdata,   // For L2
    input  wire         bus_ready,    // ?????

    // ==========================================
    // CORE-TO-CORE LINK
    // ==========================================
    output reg          link_push_req, 
    output reg  [127:0] link_data_out,
    input  wire         link_push_valid,
    input  wire [127:0] link_data_in,

    // ==========================================
    // SNOOP INTERFACE (From Arbiter)
    // ==========================================
    input  wire         snoop_req, // C0_check_L1
    input  wire  [31:0] snoop_addr, // C0_L1_address
    input  wire         snoop_type,   // 0 = Read, 1 = Write // ?????
    output reg          snoop_hit, // C0_L1_hit
    output reg          snoop_dirty // C0_L1_dirty


);

    localparam I = 3'd0;
    localparam S = 3'd1;
    localparam M = 3'd2;

    localparam IS_D = 3'd3;
    localparam IM_D = 3'd4;
    localparam SM_D = 3'd5;
   

    reg [19:0] tags [0:255];
    reg [2:0] states [0:255];

    
    wire [19:0] req_tag    = cpu_addr[31:12];
    wire [7:0]  req_index  = cpu_addr[11:4];
    wire [1:0]  req_offset = cpu_addr[3:2];

    wire [19:0] snp_tag    = snoop_addr[31:12];
    wire [7:0]  snp_index  = snoop_addr[11:4];

    reg          dcache_ctrl_we;
    reg  [127:0] dcache_ctrl_wdata;
    wire [127:0] dcache_ctrl_rdata;
    wire         dcache_cpu_we = cpu_req & cpu_we & ~cpu_stall; 

    l1D_cache dcache (
        .clk(clk),
        .index(active_index),
        .offset(req_offset),
        .word_write_enable(dcache_cpu_we),
        .word_write_data(cpu_wdata),
        .word_read_data(cpu_rdata),
        .ctrl_write_enable(dcache_ctrl_we),
        .ctrl_write_data(dcache_ctrl_wdata),
        .ctrl_read_data(dcache_ctrl_rdata)
    );



    // Hit Detection
    wire tag_match = (tag_array[req_index] == req_tag);

    // Context registers for stalls
    reg        saved_cpu_we;
    reg [31:0] saved_cpu_addr;
    reg        evict_active; // Tracks if the current bus_req is a PutM eviction

    integer i;
    always @(posedge clk or posedge reset) begin 
        if (reset) begin 
            for (i = 0; i < 256; i = i + 1) begin 
                tags[i] <= 20'b0;
                states[i] <= I;
            end
        
            cpu_stall <= 0;
            bus_req <= 0;
            bus_we <= 0;
            link_push_req <= 0;
            snoop_hit <= 0;
            snoop_dirty <= 0;
            dcache_ctrl_we <= 0;
            dcache_ctrl_wdata <= 128'b0;
            evict_active <= 0;
        end else begin 
            dcache_ctrl_we <= 0; // Default to no control write
            link_push_req <= 0; // Default to no link push


            if (snoop_req) begin
                if (tags[snp_index] == snp_tag && states[snp_index] != I) begin
                    snoop_hit <= 1;
                    if (states[snp_index] == M) begin
                        snoop_dirty <= 1;
                        link_push_req <= 1;
                        link_data_out <= dcache_ctrl_rdata; // Push dirty data to requester
                        states[snp_index] <= S; // Downgrade to Shared after pushing data

                    end
                    if (snooptype == 1) begin // IF WRITE invalidate local copy
                        states[snp_index] <= I; // Other GetM: M -> I
                    end else begin
                        states[snp_index] <= S; // Other GetS: M -> S
                    end
                end
                else if (states[snp_index] == S) begin
                    snoop_dirty <= 0; // Shared blocks are clean
                    if (snoop_type == 1) begin
                        states[snp_index] <= I; // Other GetM: S -> I
                    end
                end
            end

        end else begin
            snoop_hit <= 0;
            snoop_dirty <= 0;
        end

        else begin
            if (cpu_req && !cpu_stall) begin

                // Invalid: If it's a miss or tags are mismatched
                if (states[req_index] == I || !tag_match) begin // Not sure about why it's !tag_match..... 
                    cpu_stall <= 1;
                    saved_cpu_we <= cpu_we; // Save context for when we get the data back
                    saved_cpu_addr <= cpu_addr;

                    if (states[req_index] == M) begin
                        evict_active <= 1;
                        bus_req <= 1;
                        bus_we <= 1;
                        bus_addr <= {tags[req_index], req_index, 4'b0}; // Evict the dirty block 
                        bus_wdata <= dcache_ctrl_rdata; // Get the dirty data from the cache
                    end else begin
                        bus_req <= 1;
                        bus_addr <= cpu_addr; 
                        if (cpu_we) begin
                            bus_we <= 1; // PutM for write miss
                            states[req_index] <= IM_D; // Transition to IM_D on write miss
                        end else begin
                            bus_we <= 0; // GetS for read miss
                            states[req_index] <= IS_D; // Transition to IS_D on read miss
                        end
                    end
                end
                // Shared
                else if (states[req_index] == S && tag_match) begin
                    if (cpu_we) begin
                        cpu_stall <= 1;
                        saved_cpu_we <= cpu_we; // Save context for when we get the data back
                        saved_cpu_addr <= cpu_addr;
                        bus_req <= 1;
                        bus_we <= 1; // PutM to upgrade to Modified
                        bus_addr <= cpu_addr;
                        states[req_index] <= SM_D; // Transition to SM_D on write hit in
                    end else begin
                        cpu_stall <= 0; // Read hit in Shared state, can proceed without stalling
                    end else 
                end
        end















    end


    
    endmodule
