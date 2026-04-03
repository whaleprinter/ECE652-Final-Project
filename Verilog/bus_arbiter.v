module bus_arbiter(
    input clk,
    input reset,

    // Logic when core 0 asks bus for block
    input wire C0_request,
    input wire [31:0] C0_address,
    input wire C0_write_enable,
    output reg C0_grant,
    output reg C0_stall,

    // Logic when core 0 is asked to check its L1
    output reg C0_check_L1, // also call this snoop request
    output reg [31:0] C0_L1_address,
    input wire C0_L1_ready, // also call this snoop done 
    input wire C0_L1_hit,
    input wire C0_L1_dirty, 
    
    // Logic when core 1 asks bus for block
    input wire C1_request,
    input wire [31:0] C1_address,
    input wire C1_write_enable,
    output reg C1_ready,
    output reg C1_stall,

    // Logic when core 1 is asked to check its L1
    output reg C1_check_L1,
    output reg [31:0] C1_L1_address,
    input wire C1_L1_ready,
    input wire C1_L1_hit,
    input wire C1_L1_dirty,


    // L2 Interface. ALWAYS GOING TO BE MOVING AN ENTIRE BLOCK BETWEEN L2 AND L1, so no need for word-granularity signals. 
    input wire L2_request,
    input wire [31:0] L2_address,
    input wire L2_write_enable, // SNOOP THE L2 IF EITHER CORE ASKS FOR A BLOCK
    // output reg [31:0] L2_rdata_out,
    output reg L2_ready_out,
    // input wire [31:0] L2_wdata_in,

    input wire [127:0] L2_rdata_block_in,
    output reg [127:0] L2_wdata_block_out

    
);
    localparam IDLE = 3'd0;
    localparam SERVE_C0 = 3'd1;
    localparam SERVE_C1 = 3'd2;
    localparam ACCESS_L2 = 3'd3;

    reg [2:0] state, next_state;
    reg priority;    


    // State register and priority logic
    always @(posedge clk or posedge reset) begin 

        if (reset) begin 
            state <= IDLE;
            priority <= 0; 
        end else begin 
            state <= next_state;
            if (state != IDLE && next_state == IDLE) begin 
                priority <= ~priority; // Round robin HERE I THINK
            end
        end

    end


    always @(*) begin 

        next_state = state; 
        C0_grant = 0;
        C0_stall = 0;
        C0_check_L1 = 0;
        C0_L1_address = 32'b0;

        C1_ready = 0;
        C1_stall = 0;
        C1_check_L1 = 0;
        C1_L1_address = 32'b0;

        case (state)
            IDLE: begin 
                if (C0_request && C1_request) begin 
                    next_state = priority ? SERVE_C1 : SERVE_C0; 
                end else if (C0_request && !C1_request) begin 
                    next_state = SERVE_C0;
                end else if (!C0_request && C1_request) begin 
                    next_state = SERVE_C1;
                end
            end

            SERVE_C0: begin 
                C0_stall = 1; 
                C1_check_L1 = 1;
                C1_L1_address = C0_address;

                if (C1_L1_ready) begin 
                    C0_grant = 1; 
                    next_state = IDLE; 
                end
            end
 
            SERVE_C1: begin 
                C1_stall = 1; 
                C0_check_L1 = 1;
                C0_L1_address = C1_address;

                if (C0_L1_ready) begin 
                    C1_ready = 1; 
                    next_state = IDLE; 
                end
            end

            // TODO: ADD L2 ACCESS STATE STUFF HERE!!!!!

            default: next_state = IDLE;
        endcase
    end





endmodule



