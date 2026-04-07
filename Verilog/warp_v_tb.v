`timescale 1ns/1ps

module warp_v_tb;

    reg clk;
    reg reset;

    // Instruction interface
    wire [31:0] imem_addr;
    wire        imem_req;
    reg  [31:0] imem_rdata;
    wire        imem_stall;

    // Data interface (stubbed)
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire        dmem_we;
    wire        dmem_req;
    reg  [31:0] dmem_rdata;
    wire        dmem_stall;

    // Instantiate core
    warp_v_core uut (
        .clk(clk),
        .reset(reset),

        .imem_addr_out(imem_addr),
        .imem_req_out(imem_req),
        .imem_rdata_in(imem_rdata),
        .imem_stall_in(1'b0),   // always ready

        .dmem_addr_out(dmem_addr),
        .dmem_wdata_out(dmem_wdata),
        .dmem_we_out(dmem_we),
        .dmem_req_out(dmem_req),
        .dmem_rdata_in(dmem_rdata),
        .dmem_stall_in(1'b0)    // no stalls
    );

    // Simple instruction memory (COMBINATIONAL, SAFE HERE)
    reg [31:0] mem [0:15];

    initial begin
        // Program:
        // 0x0000: lui x15, 0x1
        // 0x0004: addi x1, x0, 5
        // 0x0008: addi x2, x0, 10
        // 0x000C: add  x3, x1, x2
        // 0x0010: nop

        mem[0] = 32'h000017b7; // lui x15,0x1
        mem[1] = 32'h00500093; // addi x1,x0,5
        mem[2] = 32'h00a00113; // addi x2,x0,10
        mem[3] = 32'h002081b3; // add x3,x1,x2
        mem[4] = 32'h00000013; // nop

        // Fill rest with nop (IMPORTANT)
        for (int i = 5; i < 16; i++)
            mem[i] = 32'h00000013;
    end

    // Instruction fetch (word aligned)
    always @(*) begin
        imem_rdata = mem[imem_addr[31:2]];
    end

    // Data memory (not used, return 0)
    always @(*) begin
        dmem_rdata = 32'h0;
    end

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset
    initial begin
        reset = 1;
        repeat (10) @(posedge clk);  // HOLD RESET LONGER
        reset = 0;
    end

    // Debug prints
    always @(posedge clk) begin
        if (!reset) begin
            $display("PC=%h INSTR=%h", imem_addr, imem_rdata);
        end
    end

    // Stop simulation
    initial begin
        #500;
        $display("Finished");
        $finish;
    end

endmodule