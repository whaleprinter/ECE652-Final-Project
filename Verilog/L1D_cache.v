module L1D_cache(
    input wire clk,

    // ==========================================
    // PORT A: CPU Interface (Words Only)
    // ==========================================
    input wire [7:0] cpu_index,
    input wire [1:0] offset,
    input wire [31:0] word_write_data,
    input wire word_write_enable,
    output reg [31:0] word_read_data,

    // ==========================================
    // PORT B: Controller / Core-to-Core Interface (128-bit)
    // ==========================================
    input wire [7:0] ctrl_index,
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

    // Combinatorial Reads (Independent Ports!)
    always @(*) begin
        // The Controller can read its block instantly
        ctrl_read_data = cache[ctrl_index];
        
        // The CPU can read its word instantly
        case (offset)
            2'b00: word_read_data = cache[cpu_index][31:0];
            2'b01: word_read_data = cache[cpu_index][63:32];
            2'b10: word_read_data = cache[cpu_index][95:64];
            2'b11: word_read_data = cache[cpu_index][127:96];
        endcase
    end

    // Synchronous Writes (Independent Ports!)
    always @(posedge clk) begin
        // Controller Write
        if (ctrl_write_enable) begin
            cache[ctrl_index] <= ctrl_write_data;
        end
        
        // CPU Write
        if (word_write_enable) begin
            case (offset)
                2'b00: cache[cpu_index][31:0]   <= word_write_data;
                2'b01: cache[cpu_index][63:32]  <= word_write_data;
                2'b10: cache[cpu_index][95:64]  <= word_write_data;
                2'b11: cache[cpu_index][127:96] <= word_write_data;
            endcase
        end
    end

endmodule



// endmodule
