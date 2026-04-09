module L1I_cache #(
    parameter INIT_FILE = "program.hex" 
)(
    input wire clk,
    input wire reset,
    input wire [31:0] address,
    output wire [31:0] data  // CHANGED from reg to wire
);

    reg [7:0] cache [0:4095];

    initial begin 
        integer i;
        for (i = 0; i < 4096; i = i + 1) cache[i] = 8'b0;
        
        $readmemh(INIT_FILE, cache); 
    end

    assign data = {cache[address+3], cache[address+2], cache[address+1], cache[address]};

endmodule