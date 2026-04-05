module L1I_cache #(

    parameter INIT_FILE = "program.hex" 
)(
    input wire clk,
    input wire reset,
    input wire [31:0] address,
    output reg [31:0] data
);

    // (8 bits wide, 4096 elements)
    // 4KB total of cache.... byte addressed bc verilog is goofy
    reg [7:0] cache [0:4095];

    initial begin 

        $readmemh(INIT_FILE, cache); 
    end

    always @(posedge clk or posedge reset) begin 
        if (reset) begin 
            data <= 32'b0;
        end else begin 
            data <= {cache[address+3], cache[address+2], cache[address+1], cache[address]};
        end
    end


endmodule
