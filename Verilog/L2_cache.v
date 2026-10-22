module L2_cache #(
    parameter INIT_FILE = ""     // Optional byte-addressed image ($readmemh / objcopy -O verilog)
)(
    input wire clk,
    input wire reset,
    input wire req,
    input wire [31:0] addr,
    input wire we,
    input wire [127:0] wdata,
    output reg [127:0] rdata,
    output reg ready
);

    // TODO: Add an "owner or not owner" bit
    reg [127:0] cache [0:1023]; // 16 byte cache blocks. 1024 blocks. 16 KB total cache size 
    integer i;
    reg [7:0] image [0:16383];
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            // $display("Initializing cache block %0d", i);
            cache[i] = 128'd0;
        end
        if (INIT_FILE != "") begin
            for (i = 0; i < 16384; i = i + 1) image[i] = 8'b0;
            $readmemh(INIT_FILE, image);
            for (i = 0; i < 16384; i = i + 1)
                cache[i / 16][(i % 16) * 8 +: 8] = image[i];
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            ready <= 1'b0; 
            rdata <= 128'b0;
        end else begin
            

            if (req && !ready) begin

                // No tags: addresses at or above 16 KB alias onto lower blocks
                if (addr[31:14] != 0)
                    $display("L2_ERROR: address 0x%08h is outside the 16 KB memory (aliases 0x%04h)", addr, addr[13:0]);
                
                ready <= 1'b1; 
                

                if (we) begin
                    // Write
                    cache[addr[13:4]] <= wdata;
                end else begin
                    // Read
                    rdata <= cache[addr[13:4]];
                end
                
            end else begin

                ready <= 1'b0;
            end
            
        end
    end



endmodule
