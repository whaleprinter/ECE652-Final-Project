module bus_arbiter (
    input wire clk,
    input wire reset,

    // Core 0
    input  wire         c0_bus_req,
    input  wire  [31:0] c0_bus_addr,
    input  wire         c0_bus_we,      // 0 = GetS, 1 = GetM
    input  wire         c0_bus_put,     // 1 = PutM (writeback c0_bus_wdata)
    output reg          c0_bus_grant,
    output reg  [127:0] c0_bus_rdata,
    input  wire [127:0] c0_bus_wdata,
    output reg          c0_bus_ready,

    output reg          c0_snoop_req,
    output reg   [31:0] c0_snoop_addr,
    output reg          c0_snoop_type,
    input  wire         c0_snoop_hit,
    input  wire         c0_snoop_dirty,
    input  wire [127:0] c0_link_data,   // Block Core 0 is forwarding over the link

    // Core 1
    input  wire         c1_bus_req,
    input  wire  [31:0] c1_bus_addr,
    input  wire         c1_bus_we,
    input  wire         c1_bus_put,
    output reg          c1_bus_grant,
    output reg  [127:0] c1_bus_rdata,
    input  wire [127:0] c1_bus_wdata,
    output reg          c1_bus_ready,

    output reg          c1_snoop_req,
    output reg   [31:0] c1_snoop_addr,
    output reg          c1_snoop_type,
    input  wire         c1_snoop_hit,
    input  wire         c1_snoop_dirty,
    input  wire [127:0] c1_link_data,

    // L2
    output reg          l2_req,
    output reg   [31:0] l2_addr,
    output reg          l2_we,
    output reg  [127:0] l2_wdata,
    input  wire [127:0] l2_rdata,
    input  wire         l2_ready
);

    // FSM States

    // Cores can only make requests on their designated cycles.
    localparam IDLE      = 3'd0;
    localparam SNOOP_C1  = 3'd1;
    localparam SNOOP_C0  = 3'd2;
    localparam ACCESS_L2 = 3'd3;
    localparam WB_LATCH  = 3'd4;   // Dirty block forwarded for a GetS: capture it from the link...
    localparam WB_L2     = 3'd5;   // ...and write it to L2 so the S copies match memory

    reg [2:0] state;
    reg core_priority;    // 0 = Core 0 core_priority, 1 = Core 1 core_priority
    reg serving_c0;  // Tracks who currently owns the bus transaction

    // Request latched at grant so the transaction can't change underneath us
    reg  [31:0] req_addr;
    reg         req_we;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            core_priority <= 0;
            c0_bus_grant <= 0; c1_bus_grant <= 0;
            c0_bus_ready <= 0; c1_bus_ready <= 0;
            c0_snoop_req <= 0; c1_snoop_req <= 0;
            l2_req <= 0; l2_we <= 0; l2_wdata <= 0;
            c0_snoop_addr <= 0; c1_snoop_addr <= 0;
            c0_bus_rdata <= 128'b0;
            c1_bus_rdata <= 128'b0; 
            serving_c0 <= 0;
            req_addr <= 0; req_we <= 0;
        end else begin

            c0_bus_ready <= 0;
            c1_bus_ready <= 0;

            case (state)
                IDLE: begin
                    l2_req <= 0;
                    c0_snoop_req <= 0;
                    c1_snoop_req <= 0;
                    

                    // Round robin when both cores request
                    if (c0_bus_req && (!c1_bus_req || core_priority == 0)) begin
                        serving_c0 <= 1;
                        c0_bus_grant <= 1;
                        req_addr <= c0_bus_addr;
                        req_we <= c0_bus_we;
                        if (c0_bus_put) begin
                            // PutM: the writer is the only holder, so no snoop needed
                            l2_req <= 1;
                            l2_addr <= c0_bus_addr;
                            l2_we <= 1;
                            l2_wdata <= c0_bus_wdata;
                            state <= ACCESS_L2;
                        end else begin
                            c1_snoop_req <= 1;
                            c1_snoop_addr <= c0_bus_addr;
                            c1_snoop_type <= c0_bus_we;
                            state <= SNOOP_C1;
                        end
                    end
                    else if (c1_bus_req) begin
                        serving_c0 <= 0;
                        c1_bus_grant <= 1;
                        req_addr <= c1_bus_addr;
                        req_we <= c1_bus_we;
                        if (c1_bus_put) begin
                            l2_req <= 1;
                            l2_addr <= c1_bus_addr;
                            l2_we <= 1;
                            l2_wdata <= c1_bus_wdata;
                            state <= ACCESS_L2;
                        end else begin
                            c0_snoop_req <= 1;
                            c0_snoop_addr <= c1_bus_addr;
                            c0_snoop_type <= c1_bus_we;
                            state <= SNOOP_C0;
                        end
                    end
                end

                SNOOP_C1: begin
                    c1_snoop_req <= 0; 
                    
                    if (c1_snoop_dirty) begin
                        // Data sent from other core
                        c0_bus_ready <= 1;
                        c0_bus_grant <= 0;
                        core_priority <= 1;
                        // M -> S leaves two clean copies, so L2 must be updated too
                        state <= req_we ? IDLE : WB_LATCH;
                    end else begin
                        // Go to L2 for data (GetS and GetM both read)
                        l2_req <= 1;
                        l2_addr <= req_addr;
                        l2_we <= 0;
                        state <= ACCESS_L2;
                    end
                end

                SNOOP_C0: begin
                    c0_snoop_req <= 0; 
                    
                    if (c0_snoop_dirty) begin
                        c1_bus_ready <= 1;
                        c1_bus_grant <= 0;
                        core_priority <= 0;
                        state <= req_we ? IDLE : WB_LATCH;
                    end else begin
                        l2_req <= 1;
                        l2_addr <= req_addr;
                        l2_we <= 0;
                        state <= ACCESS_L2;
                    end
                end

                ACCESS_L2: begin
                    if (l2_ready) begin
                        l2_req <= 0; 
                        
                        if (serving_c0) begin
                            c0_bus_rdata <= l2_rdata;
                            c0_bus_ready <= 1;
                            c0_bus_grant <= 0;
                        end else begin
                            c1_bus_rdata <= l2_rdata;
                            c1_bus_ready <= 1;
                            c1_bus_grant <= 0;
                        end
                        
                        // Give priority to the core that was not just served
                        core_priority <= serving_c0;
                        state <= IDLE;
                    end
                end

                // The snooped core drives its block on the link the cycle after the snoop
                WB_LATCH: begin
                    l2_req <= 1;
                    l2_addr <= req_addr;
                    l2_we <= 1;
                    l2_wdata <= serving_c0 ? c1_link_data : c0_link_data;
                    state <= WB_L2;
                end

                WB_L2: begin
                    if (l2_ready) begin
                        l2_req <= 0;
                        l2_we <= 0;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule