`timescale 1ns / 1ps

module tb_naked_core();
    reg clk;
    reg reset;

    // CPU Outputs
    wire [31:0] dmem_addr_out, dmem_wdata_out;
    wire dmem_we_out, dmem_req_out;
    wire [31:0] imem_addr_out;
    wire imem_req_out;

    // Instantiate just the CPU
    warp_v_core uut (
        .clk(clk),
        .reset(reset),
        
        // Tie Data Memory to always return 0 and never stall
        .dmem_rdata_in(32'b0),
        .dmem_stall_in(1'b0),
        
        .dmem_addr_out(dmem_addr_out),
        .dmem_wdata_out(dmem_wdata_out),
        .dmem_we_out(dmem_we_out),
        .dmem_req_out(dmem_req_out),

        // Hardcode the Instruction Memory to always return NOP (addi x0, x0, 0)
        // and never stall.
        .imem_rdata_in(32'h000017B7),
        .imem_stall_in(1'b0),
        
        .imem_addr_out(imem_addr_out),
        .imem_req_out(imem_req_out)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("naked_core.vcd");
        $dumpvars(0, tb_naked_core);

        clk = 0;
        
        // Test Active-High Reset
        reset = 1;
        repeat(5) @(negedge clk);
        reset = 0;
        
        // Let it run for a few cycles
        repeat(10) @(negedge clk);
        
        $display("Test Complete.");
        $finish;
    end
endmodule