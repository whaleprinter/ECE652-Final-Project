module L1I_cache (
    input wire clk,
    input wire reset,
    input wire [31:0] address,
    output reg [31:0] data
);

    reg [31:0] cache [0:1023]; // Should be 4 KB of cache (1024 lines of 32 bits each)??

    initial begin 
        $readmemb("program.hex", cache); 
    end

    always @(posedge clk or posedge reset) begin 
        if (reset) begin 
            data <= 32'b0;
        end else begin 
            data <= cache[address[11:2]]; 
        end
    end


endmodule
