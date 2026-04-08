module L2_cache(
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
    reg [127:0] cache [0:1023]; // 16 byte cache blocks. 1023 blocks. 16 KB total cache size 
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            // $display("Initializing cache block %0d", i);
            cache[i] = 128'd99999999999;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            ready <= 1'b0; 
            rdata <= 128'b0;
        end else begin
            

            if (req && !ready) begin
                
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




    // // Read
    // always @(*) begin
    //     rdata <= cache[addr[13:4]];
    // end

    // // Write
    // always @(posedge clk) begin
    //     if (we) cache[addr[13:4]] <= wdata;
    // end

    // assign ready = 1; 





endmodule
