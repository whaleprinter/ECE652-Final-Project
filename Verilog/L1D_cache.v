module L1D_cache(
    input wire clk,

    // For CPU to write words only
    input wire [7:0] index,
    input wire[1:0] offset,
    input wire [31:0] word_write_data,
    input wire word_write_enable,
    output reg [31:0] word_read_data,

    // For controller to write ENTIRE CACHE BLOCK IN ONE CYCLE!!!!! CORE TO CORE INTERFACE
    input wire ctrl_write_enable,
    input wire [127:0] ctrl_write_data,
    output reg [127:0] ctrl_read_data
);

    reg [127:0] cache [0:255]; // 16 byte cache blocks. 256 blocks. 4 KB total cache size 

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            cache[i] = 128'b0;
        end
    end
    // Read
    always @(*) begin
        ctrl_read_data = cache[index];
        case (offset)
            2'b00: word_read_data = cache[index][31:0];
            2'b01: word_read_data = cache[index][63:32];
            2'b10: word_read_data = cache[index][95:64];
            2'b11: word_read_data = cache[index][127:96];
        endcase
    end

    // Write
    always @(posedge clk) begin
        if (ctrl_write_enable)
            cache[index] <= ctrl_write_data;
        else if (word_write_enable)
            case (offset)
                2'b00: cache[index][31:0]   <= word_write_data;
                2'b01: cache[index][63:32]  <= word_write_data;
                2'b10: cache[index][95:64]  <= word_write_data;
                2'b11: cache[index][127:96] <= word_write_data;
            endcase
    end






endmodule
