`timescale 1ns / 1ps

module tb_warp_v_core();
    reg clk;
    reg reset;
    
    // Memory interface wires
    wire [31:0] dmem_addr_out;
    wire [31:0] dmem_wdata_out;
    wire dmem_we_out;
    wire dmem_req_out;
    reg  [31:0] dmem_rdata_in;
    reg  dmem_stall_in;

    // Instantiate the raw WARP-V CPU
    warp_v_core uut (
        .clk(clk),
        .reset(reset),
        .dmem_addr_out(dmem_addr_out),
        .dmem_wdata_out(dmem_wdata_out),
        .dmem_we_out(dmem_we_out),
        .dmem_req_out(dmem_req_out),
        .dmem_rdata_in(dmem_rdata_in),
        .dmem_stall_in(dmem_stall_in)
    );

    // Clock generation (10ns period)
    always #5 clk = ~clk;

    // Fake Data Memory Array (64 words)
    reg [31:0] fake_mem [0:63];

    // Dummy Memory Response Logic
    always @(posedge clk) begin
        if (reset) begin
            dmem_rdata_in <= 0;
            dmem_stall_in <= 0;
        end else begin
            // Never stall the CPU in this isolated test
            dmem_stall_in <= 0; 
            
            if (dmem_req_out) begin
                // Handle Writes
                if (dmem_we_out) begin
                    fake_mem[dmem_addr_out[7:2]] <= dmem_wdata_out;
                end 
                // Handle Reads
                else begin
                    dmem_rdata_in <= fake_mem[dmem_addr_out[7:2]];
                end
            end
        end
    end

    initial begin
        $dumpfile("warp_v_cpu.vcd");
        $dumpvars(0, tb_warp_v_core);

        // Initialize
        clk = 0;
        reset = 1;

        // Hold reset for a few cycles, release on negedge
        repeat(4) @(negedge clk);
        reset = 0;

        // Let the internal Makerchip test program run 
        // 200 clock cycles is plenty to see memory activity
        repeat(200) @(negedge clk);
        
        $display("CPU Test Simulation Complete.");
        $finish;
    end
endmodule