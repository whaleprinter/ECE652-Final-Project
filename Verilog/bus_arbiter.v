module bus_arbiter (
    input wire clk,
    input wire reset,

    // Core 0
    input  wire         c0_bus_req,
    input  wire  [31:0] c0_bus_addr,
    input  wire         c0_bus_we,
    output reg          c0_bus_grant,
    output reg  [127:0] c0_bus_rdata,
    input  wire [127:0] c0_bus_wdata,
    output reg          c0_bus_ready,

    output reg          c0_snoop_req,
    output reg   [31:0] c0_snoop_addr,
    output reg          c0_snoop_type,
    input  wire         c0_snoop_hit,
    input  wire         c0_snoop_dirty,

    // Core 1
    input  wire         c1_bus_req,
    input  wire  [31:0] c1_bus_addr,
    input  wire         c1_bus_we,
    output reg          c1_bus_grant,
    output reg  [127:0] c1_bus_rdata,
    input  wire [127:0] c1_bus_wdata,
    output reg          c1_bus_ready,

    output reg          c1_snoop_req,
    output reg   [31:0] c1_snoop_addr,
    output reg          c1_snoop_type,
    input  wire         c1_snoop_hit,
    input  wire         c1_snoop_dirty,

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

    reg [2:0] state;
    reg core_priority;    // 0 = Core 0 core_priority, 1 = Core 1 core_priority
    reg serving_c0;  // Tracks who currently owns the bus transaction

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
        end else begin

            c0_bus_ready <= 0;
            c1_bus_ready <= 0;

            case (state)
                IDLE: begin
                    l2_req <= 0;
                    c0_snoop_req <= 0;
                    c1_snoop_req <= 0;
                    

                    // Other core will be in transient state
                    if (c0_bus_req && c1_bus_req) begin
                        if (core_priority == 0) begin
                            serving_c0 <= 1;
                            c0_bus_grant <= 1;
                            c1_snoop_req <= 1;
                            c1_snoop_addr <= c0_bus_addr;
                            c1_snoop_type <= c0_bus_we;
                            state <= SNOOP_C1;
                        end else begin
                            serving_c0 <= 0;
                            c1_bus_grant <= 1;
                            c0_snoop_req <= 1;
                            c0_snoop_addr <= c1_bus_addr;
                            c0_snoop_type <= c1_bus_we;
                            state <= SNOOP_C0;
                        end
                    end 
                    else if (c0_bus_req) begin
                        serving_c0 <= 1;
                        c0_bus_grant <= 1;
                        c1_snoop_req <= 1;
                        c1_snoop_addr <= c0_bus_addr;
                        c1_snoop_type <= c0_bus_we;
                        state <= SNOOP_C1;
                    end 
                    else if (c1_bus_req) begin
                        serving_c0 <= 0;
                        c1_bus_grant <= 1;
                        c0_snoop_req <= 1;
                        c0_snoop_addr <= c1_bus_addr;
                        c0_snoop_type <= c1_bus_we;
                        state <= SNOOP_C0;
                    end
                end

                SNOOP_C1: begin
                    c1_snoop_req <= 0; 
                    
                    if (c1_snoop_dirty) begin
                        // Data sent from other core
                        c0_bus_ready <= 1;
                        c0_bus_grant <= 0;
                        core_priority <= ~core_priority; 
                        state <= IDLE;
                    end else begin
                        // Go to L2 for data
                        l2_req <= 1;
                        l2_addr <= c0_bus_addr;
                        l2_we <= c0_bus_we;
                        l2_wdata <= c0_bus_wdata;
                        state <= ACCESS_L2;
                    end
                end

                SNOOP_C0: begin
                    c0_snoop_req <= 0; 
                    
                    if (c0_snoop_dirty) begin
                        c1_bus_ready <= 1;
                        c1_bus_grant <= 0;
                        core_priority <= ~core_priority;
                        state <= IDLE;
                    end else begin
                        l2_req <= 1;
                        l2_addr <= c1_bus_addr;
                        l2_we <= c1_bus_we;
                        l2_wdata <= c1_bus_wdata;
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
                        
                        core_priority <= ~core_priority;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule