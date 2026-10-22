`timescale 1ns / 1ps

// Self-checking system testbench.
//  - Each core signals completion by writing 1 to x30 and its result to x31.
//  - Expected results are passed as plusargs: +C0_EXPECT=<n> +C1_EXPECT=<n>
//  - Every idle bus cycle (unless +NO_INVARIANTS), the coherence invariants are checked:
//      SWMR:       a block is never M in one L1 while valid in the other
//      Data-value: a block held in S matches the copy in L2

`ifndef TIMEOUT_CYCLES
`define TIMEOUT_CYCLES 200000
`endif

module tb_coherence;
    reg clk = 0;
    reg reset = 1;

    wire [31:0] c0_r30, c0_r31;
    wire [31:0] c1_r30, c1_r31;

    system_top dut (
        .clk(clk),
        .reset(reset),
        .c0_r30(c0_r30), .c0_r31(c0_r31),
        .c1_r30(c1_r30), .c1_r31(c1_r31)
    );

    always #5 clk = ~clk;

    localparam S = 3'd1;
    localparam M = 3'd2;

    reg [31:0] c0_expect, c1_expect;
    reg c0_done = 0, c1_done = 0;
    reg check_invariants;
    integer errors = 0;
    integer cycles = 0;
    integer i;

    initial begin
        if (!$value$plusargs("C0_EXPECT=%d", c0_expect)) c0_expect = 0;
        if (!$value$plusargs("C1_EXPECT=%d", c1_expect)) c1_expect = 0;
        check_invariants = !$test$plusargs("NO_INVARIANTS");
        repeat (2) @(negedge clk);
        reset = 0;
    end

    // Coherence invariant monitor
    always @(negedge clk) begin
        if (check_invariants && !reset && dut.arbiter.state == 0) begin
            for (i = 0; i < 256; i = i + 1) begin
                if (dut.core0_l1.tags[i] == dut.core1_l1.tags[i]) begin
                    if ((dut.core0_l1.states[i] == M && (dut.core1_l1.states[i] == M || dut.core1_l1.states[i] == S)) ||
                        (dut.core1_l1.states[i] == M && dut.core0_l1.states[i] == S)) begin
                        if (errors < 10)
                            $display("INVARIANT_FAIL cycle %0d: SWMR violated at block 0x%08h (C0=%0d C1=%0d)",
                                     cycles, {dut.core0_l1.tags[i], i[7:0], 4'b0},
                                     dut.core0_l1.states[i], dut.core1_l1.states[i]);
                        errors = errors + 1;
                    end
                end
                if (dut.core0_l1.states[i] == S &&
                    dut.core0_l1.dcache.cache[i] !== dut.main_memory.cache[{dut.core0_l1.tags[i][1:0], i[7:0]}]) begin
                    if (errors < 10)
                        $display("INVARIANT_FAIL cycle %0d: C0 S copy of 0x%08h differs from L2 (L1=%h L2=%h)",
                                 cycles, {dut.core0_l1.tags[i], i[7:0], 4'b0}, dut.core0_l1.dcache.cache[i],
                                 dut.main_memory.cache[{dut.core0_l1.tags[i][1:0], i[7:0]}]);
                    errors = errors + 1;
                end
                if (dut.core1_l1.states[i] == S &&
                    dut.core1_l1.dcache.cache[i] !== dut.main_memory.cache[{dut.core1_l1.tags[i][1:0], i[7:0]}]) begin
                    if (errors < 10)
                        $display("INVARIANT_FAIL cycle %0d: C1 S copy of 0x%08h differs from L2 (L1=%h L2=%h)",
                                 cycles, {dut.core1_l1.tags[i], i[7:0], 4'b0}, dut.core1_l1.dcache.cache[i],
                                 dut.main_memory.cache[{dut.core1_l1.tags[i][1:0], i[7:0]}]);
                    errors = errors + 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        cycles <= cycles + 1;

        if (!reset && c0_r30 == 1 && !c0_done) begin
            c0_done = 1;
            $display("C0 done at cycle %0d: x31 = %0d (expected %0d)", cycles, c0_r31, c0_expect);
            if (c0_r31 !== c0_expect) errors = errors + 1;
        end
        if (!reset && c1_r30 == 1 && !c1_done) begin
            c1_done = 1;
            $display("C1 done at cycle %0d: x31 = %0d (expected %0d)", cycles, c1_r31, c1_expect);
            if (c1_r31 !== c1_expect) errors = errors + 1;
        end

        if (c0_done && c1_done) begin
            if (errors == 0) $display("TEST_PASS");
            else             $display("TEST_FAIL (%0d errors)", errors);
            $finish;
        end

        if (cycles > `TIMEOUT_CYCLES) begin
            $display("TEST_FAIL (timeout: c0_done=%0d c1_done=%0d)", c0_done, c1_done);
            $finish;
        end
    end
endmodule
