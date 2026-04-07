module L2_cache(
    input wire clk,
    input wire req,
    input wire [31:0] addr,
    input wire we,
    input wire [127:0] wdata,
    output reg [127:0] rdata,
    output reg ready
);

    reg [127:0] cache [0:1023]; // 16 byte cache blocks. 1023 blocks. 16 KB total cache size 
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            cache[i] = 128'b0;
        end
    end

    // Read
    always @(*) begin
        rdata <= cache[addr[13:4]];
    end

    // Write
    always @(posedge clk) begin
        if (we) cache[addr[13:4]] <= wdata;
    end






endmodule
