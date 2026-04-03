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

    // Write logic
    always @(posedge clk) begin 
        if (ctrl_write_enable) begin    
            cache[index] <= ctrl_write_data; // for cache-to-cahce transfers, write the whole block at once
        end else if (word_write_enable) begin 
            case (offset) // For writes from the CPU, only write the correct word within the block
                2'b00: cache[index][31:0] <= word_write_data;
                2'b01: cache[index][63:32] <= word_write_data;
                2'b10: cache[index][95:64] <= word_write_data;
                2'b11: cache[index][127:96] <= word_write_data;
            endcase
        end

    ctrl_read_data <= cache[index]; // for cache-to-cache transfers, read the whole block at once
    case (offset) // For reads to the CPU, only read the correct word within the block
        2'b00: word_read_data <= cache[index][31:0];
        2'b01: word_read_data <= cache[index][63:32];
        2'b10: word_read_data <= cache[index][95:64];
        2'b11: word_read_data <= cache[index][127:96];
    endcase

    end







endmodule
