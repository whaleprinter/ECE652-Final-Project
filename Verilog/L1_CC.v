 module L1_CC (

    input  wire         clk,
    input  wire         reset,

    // Core                             // ROSHAN THESE ARE THE WIRE NAMES!!!!!
    input  wire         cpu_req,        // dmem_req_out
    input  wire  [31:0] cpu_addr,       // dmem_addr_out
    input  wire         cpu_we,         // dmem_we_out
    input  wire  [31:0] cpu_wdata,      // dmem_wdata_out
    output wire  [31:0] cpu_rdata,      // dmem_rdata_in
    output reg          cpu_stall,      // dmem_stall_in

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
    output reg  [127:0] link_data_out,  // Data being forwarded
    input  wire         link_push_valid,// Incoming C2C data is valid this cycle
    input  wire [127:0] link_data_in,   // Incoming C2C forwarded data

    // Snooping
    input  wire         snoop_req,      // C0_check_L1
    input  wire  [31:0] snoop_addr,     // C0_L1_address
    input  wire         snoop_type,     // 0=GetS (read), 1=GetM (write/invalidate)
    output reg          snoop_hit,      // C0_L1_hit
    output reg          snoop_dirty     // C0_L1_dirty
);

    
    localparam I    = 3'd0; 
    localparam S    = 3'd1; 
    localparam M    = 3'd2; 
    localparam IS_D = 3'd3; 
    localparam IM_D = 3'd4; 
    localparam SM_D = 3'd5; 

    reg [19:0] tags   [0:255];
    reg  [2:0] states [0:255];

    //   [31:12] tag 
    //   [11:4]  index 
    //   [3:2]   word offset
    //   [1:0]   byte offset 

    wire [19:0] req_tag    = cpu_addr[31:12];
    wire  [7:0] req_index  = cpu_addr[11:4];
    wire  [1:0] req_offset = cpu_addr[3:2];

    wire [19:0] snp_tag   = snoop_addr[31:12];
    wire  [7:0] snp_index = snoop_addr[11:4];

    wire [7:0] active_index = snoop_req ? snp_index : req_index;

    reg          dcache_ctrl_we;
    reg  [127:0] dcache_ctrl_wdata;
    wire [127:0] dcache_ctrl_rdata;

    // Word write enable: only write CPU data when needed
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

    // Detect cache hit
    wire tag_match = (tags[req_index] == req_tag);
    wire hit       = tag_match && (states[req_index] != I);


    // Need to save the CPU's original request address and write enable so that we can re-issue the correct bus request after evicting a dirty block 
    reg        saved_cpu_we;
    reg [31:0] saved_cpu_addr;

    // Tracks whether the outstanding bus request is a dirty eviction
    reg evict_active;


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

           
            dcache_ctrl_we <= 0;
            link_push_req  <= 0;
            snoop_hit      <= 0;
            snoop_dirty    <= 0;

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
                                // GetM --> S → I  
                                states[snp_index] <= I;
                            end
                            // GetS on S: no state change needed
                        end

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
            end

            // Response

            if (bus_grant)
                bus_req <= 0;

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
                    cpu_stall <= 0;

                    // Resolve transient states
                    case (states[saved_cpu_addr[11:4]])
                        IS_D:         states[saved_cpu_addr[11:4]] <= S;
                        IM_D, SM_D:   states[saved_cpu_addr[11:4]] <= M;
                        default: ;  
                    endcase
                end
            end

            // CPU Request Handling
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
                                bus_we             <= 1;   // GetM 
                                bus_addr           <= cpu_addr;
                                states[req_index]  <= SM_D;
                            end
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



