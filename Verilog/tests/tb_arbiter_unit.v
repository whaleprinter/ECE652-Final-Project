`timescale 1ns / 1ps

// Unit test for bus_arbiter + L2_cache with the L1 controllers modelled by tasks.

module tb_arbiter_unit;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;

    reg          c0_req = 0, c0_we = 0, c0_put = 0;
    reg  [31:0]  c0_addr = 0;
    reg  [127:0] c0_wdata = 0;
    wire         c0_grant, c0_ready;
    wire [127:0] c0_rdata;
    wire         c0_snoop_req, c0_snoop_type;
    wire [31:0]  c0_snoop_addr;
    reg          c0_has_dirty = 0;
    reg  [127:0] c0_link = 0;

    reg          c1_req = 0, c1_we = 0, c1_put = 0;
    reg  [31:0]  c1_addr = 0;
    reg  [127:0] c1_wdata = 0;
    wire         c1_grant, c1_ready;
    wire [127:0] c1_rdata;
    wire         c1_snoop_req, c1_snoop_type;
    wire [31:0]  c1_snoop_addr;
    reg          c1_has_dirty = 0;
    reg  [127:0] c1_link = 0;

    wire         l2_req, l2_we, l2_ready;
    wire [31:0]  l2_addr;
    wire [127:0] l2_wdata, l2_rdata;

    bus_arbiter dut (
        .clk(clk), .reset(reset),
        .c0_bus_req(c0_req), .c0_bus_addr(c0_addr), .c0_bus_we(c0_we), .c0_bus_put(c0_put),
        .c0_bus_grant(c0_grant), .c0_bus_rdata(c0_rdata), .c0_bus_wdata(c0_wdata), .c0_bus_ready(c0_ready),
        .c0_snoop_req(c0_snoop_req), .c0_snoop_addr(c0_snoop_addr), .c0_snoop_type(c0_snoop_type),
        .c0_snoop_hit(c0_snoop_req && c0_has_dirty), .c0_snoop_dirty(c0_snoop_req && c0_has_dirty),
        .c0_link_data(c0_link),
        .c1_bus_req(c1_req), .c1_bus_addr(c1_addr), .c1_bus_we(c1_we), .c1_bus_put(c1_put),
        .c1_bus_grant(c1_grant), .c1_bus_rdata(c1_rdata), .c1_bus_wdata(c1_wdata), .c1_bus_ready(c1_ready),
        .c1_snoop_req(c1_snoop_req), .c1_snoop_addr(c1_snoop_addr), .c1_snoop_type(c1_snoop_type),
        .c1_snoop_hit(c1_snoop_req && c1_has_dirty), .c1_snoop_dirty(c1_snoop_req && c1_has_dirty),
        .c1_link_data(c1_link),
        .l2_req(l2_req), .l2_addr(l2_addr), .l2_we(l2_we), .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata), .l2_ready(l2_ready)
    );

    L2_cache l2 (
        .clk(clk), .reset(reset), .req(l2_req), .addr(l2_addr), .we(l2_we),
        .wdata(l2_wdata), .rdata(l2_rdata), .ready(l2_ready)
    );

    integer errors = 0;
    task check(input cond, input [8*64-1:0] msg);
        begin
            if (cond) $display("  PASS: %0s", msg);
            else begin $display("  FAIL: %0s", msg); errors = errors + 1; end
        end
    endtask

    // Monitors over the current transaction
    reg saw_c1_snoop, saw_l2_write, saw_l2_read;
    always @(posedge clk) begin
        if (c1_snoop_req) saw_c1_snoop <= 1;
        if (l2_req && l2_we) saw_l2_write <= 1;
        if (l2_req && !l2_we) saw_l2_read <= 1;
    end
    task clear_monitors; begin saw_c1_snoop = 0; saw_l2_write = 0; saw_l2_read = 0; end endtask

    // Drop each request once granted, like L1_CC does
    always @(posedge clk) begin
        if (c0_grant) c0_req <= 0;
        if (c1_grant) c1_req <= 0;
    end

    task wait_ready0; begin @(posedge clk); while (!c0_ready) @(posedge clk); end endtask
    task wait_ready1; begin @(posedge clk); while (!c1_ready) @(posedge clk); end endtask
    task wait_idle;   begin while (dut.state != 0) @(posedge clk); @(posedge clk); end endtask

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;

        $display("--- PutM writes L2 without snooping the other core ---");
        clear_monitors;
        @(negedge clk); c0_req = 1; c0_put = 1; c0_we = 0; c0_addr = 32'h100; c0_wdata = 128'hAAAA;
        @(negedge clk); c0_put = 0;
        wait_ready0; wait_idle;
        check(!saw_c1_snoop, "no snoop sent to C1 for PutM");
        check(l2.cache[32'h100 >> 4] == 128'hAAAA, "L2 holds written-back block");

        $display("--- GetM reads L2 (never writes it) ---");
        clear_monitors;
        @(negedge clk); c0_req = 1; c0_we = 1; c0_addr = 32'h100; c0_wdata = 128'hDEAD;
        wait_ready0;
        check(c0_rdata == 128'hAAAA, "GetM returns L2 data");
        wait_idle;
        check(!saw_l2_write, "no L2 write during GetM");
        check(l2.cache[32'h100 >> 4] == 128'hAAAA, "L2 unchanged by GetM");

        $display("--- Request is latched at grant ---");
        @(negedge clk); c0_req = 1; c0_we = 0; c0_addr = 32'h100;
        @(posedge clk); @(negedge clk); c0_addr = 32'h500;   // L1 moves on after grant
        wait_ready0;
        check(c0_rdata == 128'hAAAA, "L2 accessed at the granted address");
        wait_idle;

        $display("--- Dirty GetS: forwarded block is written back to L2 ---");
        @(negedge clk); c0_has_dirty = 1; c0_link = 128'hBEEF;
        c1_req = 1; c1_we = 0; c1_addr = 32'h200;
        wait_ready1; @(negedge clk); c0_has_dirty = 0;
        wait_idle;
        check(l2.cache[32'h200 >> 4] == 128'hBEEF, "L2 updated with forwarded block");

        $display("--- Dirty GetM: no writeback (requester becomes the owner) ---");
        clear_monitors;
        @(negedge clk); c0_has_dirty = 1; c0_link = 128'hF00D;
        c1_req = 1; c1_we = 1; c1_addr = 32'h300;
        wait_ready1; @(negedge clk); c0_has_dirty = 0;
        wait_idle;
        check(!saw_l2_write && !saw_l2_read, "L2 untouched");

        $display("--- Round robin: after serving C1, C0 wins a tie ---");
        @(negedge clk); c1_req = 1; c1_we = 0; c1_addr = 32'h400;
        wait_ready1; wait_idle;
        @(negedge clk); c0_req = 1; c0_we = 0; c0_addr = 32'h400;
                        c1_req = 1; c1_we = 0; c1_addr = 32'h410;
        @(posedge clk); #1;
        check(c0_grant && !c1_grant, "C0 granted first");
        wait_ready0; wait_idle;
        @(posedge clk); #1;
        check(c1_grant, "then C1");
        wait_ready1; wait_idle;

        if (errors == 0) $display("TEST_PASS");
        else             $display("TEST_FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin #20000; $display("TEST_FAIL (timeout)"); $finish; end
endmodule
