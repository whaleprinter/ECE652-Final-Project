`timescale 1ns / 1ps

// Unit test for sync_unit, focused on both cores accessing it in the same cycle.

module tb_sync_unit;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;

    reg         c0_req = 0, c0_we = 0, c1_req = 0, c1_we = 0;
    reg  [7:0]  c0_addr = 0, c1_addr = 0;
    reg  [31:0] c0_wdata = 0, c1_wdata = 0;
    wire [31:0] c0_rdata, c1_rdata;
    wire  [1:0] exited;
    wire [31:0] c0_exit_code, c1_exit_code;

    sync_unit dut (
        .clk(clk), .reset(reset),
        .c0_req(c0_req), .c0_we(c0_we), .c0_addr(c0_addr), .c0_wdata(c0_wdata), .c0_rdata(c0_rdata),
        .c1_req(c1_req), .c1_we(c1_we), .c1_addr(c1_addr), .c1_wdata(c1_wdata), .c1_rdata(c1_rdata),
        .exited(exited), .c0_exit_code(c0_exit_code), .c1_exit_code(c1_exit_code)
    );

    integer errors = 0;
    task check(input cond, input [8*64-1:0] msg);
        begin
            if (cond) $display("  PASS: %0s", msg);
            else begin $display("  FAIL: %0s", msg); errors = errors + 1; end
        end
    endtask

    // One access per core this cycle (req=0 for none); read data is sampled before the edge
    reg [31:0] r0, r1;
    task access(input q0, input w0, input [7:0] a0, input [31:0] d0,
                input q1, input w1, input [7:0] a1, input [31:0] d1);
        begin
            @(negedge clk);
            c0_req = q0; c0_we = w0; c0_addr = a0; c0_wdata = d0;
            c1_req = q1; c1_we = w1; c1_addr = a1; c1_wdata = d1;
            #1 r0 = c0_rdata; r1 = c1_rdata;
            @(posedge clk); #1;
            c0_req = 0; c1_req = 0;
        end
    endtask

    localparam RD = 1'b0, WR = 1'b1;
    integer g;

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;

        $display("--- ids ---");
        access(1, RD, 8'h00, 0, 1, RD, 8'h00, 0);
        check(r0 == 0 && r1 == 1, "CORE_ID reads 0 and 1");
        access(1, RD, 8'h04, 0, 0, RD, 0, 0);
        check(r0 == 2, "NUM_CORES = 2");

        $display("--- locks ---");
        access(1, RD, 8'h40, 0, 1, RD, 8'h40, 0);
        check(r0 == 0 && r1 == 1, "same-cycle claim: core 0 wins, core 1 sees it held");
        access(0, RD, 0, 0, 1, RD, 8'h40, 0);
        check(r1 == 1, "still held");
        access(1, WR, 8'h40, 0, 1, RD, 8'h40, 0);
        check(r1 == 1, "release and claim in one cycle: claim waits a cycle");
        access(0, RD, 0, 0, 1, RD, 8'h40, 0);
        check(r1 == 0, "core 1 acquires after the release");
        access(1, RD, 8'h44, 0, 1, RD, 8'h5C, 0);
        check(r0 == 0 && r1 == 0, "different locks are independent");

        $display("--- counters ---");
        access(1, WR, 8'h60, 10, 0, RD, 0, 0);
        access(1, RD, 8'h60, 0, 1, RD, 8'h60, 0);
        check(r0 == 10 && r1 == 11, "same-cycle fetch_add returns 10 and 11");
        access(1, RD, 8'h60, 0, 0, RD, 0, 0);
        check(r0 == 12, "counter advanced by 2");
        access(1, WR, 8'h60, 100, 1, RD, 8'h60, 0);
        check(r1 == 100, "core 1 sees core 0's same-cycle set");
        access(1, RD, 8'h60, 0, 0, RD, 0, 0);
        check(r0 == 101, "then increments it");
        access(1, RD, 8'h64, 0, 1, RD, 8'h6C, 0);
        check(r0 == 0 && r1 == 0, "other counters untouched");

        $display("--- barrier ---");
        access(1, RD, 8'h20, 0, 0, RD, 0, 0);
        g = r0;
        access(1, WR, 8'h20, 1, 0, RD, 0, 0);
        access(1, RD, 8'h20, 0, 1, RD, 8'h20, 0);
        check(r0 == g && r1 == g, "one arrival: generation unchanged");
        access(0, RD, 0, 0, 1, WR, 8'h20, 1);
        access(1, RD, 8'h20, 0, 1, RD, 8'h20, 0);
        check(r0 == g + 1 && r1 == g + 1, "both arrived: generation advances");
        access(1, WR, 8'h20, 1, 1, WR, 8'h20, 1);
        access(1, RD, 8'h20, 0, 0, RD, 0, 0);
        check(r0 == g + 2, "same-cycle arrival advances once");
        access(1, WR, 8'h20, 1, 0, RD, 0, 0);
        access(1, RD, 8'h20, 0, 0, RD, 0, 0);
        check(r0 == g + 2, "next barrier waits for core 1 again");

        $display("--- cycles / exit ---");
        access(1, RD, 8'h08, 0, 0, RD, 0, 0);
        g = r0;
        access(1, RD, 8'h08, 0, 0, RD, 0, 0);
        check(r0 == g + 1, "cycle counter counts");
        access(0, RD, 0, 0, 1, WR, 8'h14, 7);
        check(exited == 2'b10 && c1_exit_code == 7, "core 1 exit recorded");

        if (errors == 0) $display("TEST_PASS");
        else             $display("TEST_FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
