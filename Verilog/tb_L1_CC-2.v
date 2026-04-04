`timescale 1ns/1ps

// =============================================================================
//  tb_L1_CC.v  —  Testbench for L1 Cache Controller (MSI Snooping Protocol)
//
//  Key timing rules applied throughout:
//    1. ALL inputs must be stable BEFORE the rising edge that samples them.
//    2. Registered outputs (cpu_stall, bus_req, bus_we, bus_addr) are valid
//       AFTER the rising edge — check them without an extra wait cycle.
//    3. Pulse outputs (snoop_hit, snoop_dirty, link_push_req) are only valid
//       for ONE cycle after the edge that processes snoop_req. Check them
//       immediately after that edge, before the next edge clears them.
//    4. Never hold cpu_req high for more than one cycle — the controller
//       will re-evaluate on the second cycle and may corrupt saved_cpu_addr.
//    5. Always idle at least one cycle between test cases that touch the
//       same index so registered state fully settles.
//
//  Tests:
//    TC1  – Read miss          (I  → IS_D → S)
//    TC2  – Read hit           (S,  no stall)
//    TC3  – Write miss         (I  → IM_D → M)
//    TC4  – Write hit          (M,  no stall)
//    TC5  – Write hit in S     (S  → SM_D → M, upgrade)
//    TC6  – Dirty eviction     (M  → evict → IS_D → S)
//    TC7  – Snoop GetS on M    (M  → S, dirty forwarded)
//    TC8  – Snoop GetM on M    (M  → I)
//    TC9  – Snoop GetM on S    (S  → I)
//    TC10 – Snoop miss         (no hit, no dirty)
// =============================================================================

module tb_L1_CC;

    // ── Clock ────────────────────────────────────────────────────────────────
    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz, period = 10 ns

    // ── DUT ports ────────────────────────────────────────────────────────────
    reg         cpu_req;
    reg  [31:0] cpu_addr;
    reg         cpu_we;
    reg  [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_stall;

    wire        bus_req;
    wire [31:0] bus_addr;
    wire        bus_we;
    reg         bus_grant;
    reg [127:0] bus_rdata;
    wire[127:0] bus_wdata;
    reg         bus_ready;

    wire        link_push_req;
    wire[127:0] link_data_out;
    reg         link_push_valid;
    reg [127:0] link_data_in;

    reg         snoop_req;
    reg  [31:0] snoop_addr;
    reg         snoop_type;
    wire        snoop_hit;
    wire        snoop_dirty;

    // ── DUT ──────────────────────────────────────────────────────────────────
    L1_CC dut (
        .clk(clk),               .reset(reset),
        .cpu_req(cpu_req),        .cpu_addr(cpu_addr),
        .cpu_we(cpu_we),          .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),    .cpu_stall(cpu_stall),
        .bus_req(bus_req),        .bus_addr(bus_addr),
        .bus_we(bus_we),          .bus_grant(bus_grant),
        .bus_rdata(bus_rdata),    .bus_wdata(bus_wdata),
        .bus_ready(bus_ready),
        .link_push_req(link_push_req), .link_data_out(link_data_out),
        .link_push_valid(link_push_valid), .link_data_in(link_data_in),
        .snoop_req(snoop_req),    .snoop_addr(snoop_addr),
        .snoop_type(snoop_type),
        .snoop_hit(snoop_hit),    .snoop_dirty(snoop_dirty)
    );

    // ── Scoreboard ───────────────────────────────────────────────────────────
    integer pass_count, fail_count;

    task check;
        input [63:0]  got;
        input [63:0]  expected;
        input [255:0] name;
        begin
            if (got === expected) begin
                $display("  PASS: %s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %s  got=%0h  expected=%0h", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── reset_dut ────────────────────────────────────────────────────────────
    task reset_dut;
        begin
            reset           = 1;
            cpu_req         = 0;  cpu_we    = 0;
            cpu_addr        = 0;  cpu_wdata = 0;
            bus_grant       = 0;  bus_rdata = 0;  bus_ready = 0;
            link_push_valid = 0;  link_data_in  = 0;
            snoop_req       = 0;  snoop_addr    = 0;  snoop_type = 0;
            @(posedge clk);
            @(posedge clk);
            reset = 0;
            @(posedge clk);
        end
    endtask

    // ── cpu_request ──────────────────────────────────────────────────────────
    // Pulse cpu_req for exactly one clock edge.
    // Caller must set cpu_addr/cpu_we/cpu_wdata BEFORE calling this.
    // Registered outputs are valid immediately after this task returns.
    task cpu_request;
        begin
            cpu_req = 1;
            @(posedge clk); // controller samples on this edge
            cpu_req = 0;
        end
    endtask

    // ── bus_complete ─────────────────────────────────────────────────────────
    // Simulate one full bus transaction:
    //   1. Grant bus for one cycle
    //   2. Two cycles of bus latency
    //   3. Assert bus_ready with data for one cycle
    // After this task returns, the controller has processed bus_ready.
    task bus_complete;
        input [127:0] rdata;
        begin
            @(posedge clk);
            bus_grant = 1;
            @(posedge clk);
            bus_grant = 0;
            @(posedge clk);
            @(posedge clk);
            bus_rdata = rdata;
            bus_ready = 1;
            @(posedge clk); // controller processes bus_ready on this edge
            bus_ready = 0;
        end
    endtask

    // ── do_snoop ─────────────────────────────────────────────────────────────
    // Assert snoop_req for exactly one cycle and capture pulse outputs.
    // snoop_hit/dirty/link_push_req are only valid for one cycle — this task
    // captures them into regs before the next edge clears them.
    reg cap_snoop_hit, cap_snoop_dirty, cap_link_push;

    task do_snoop;
        input [31:0] addr;
        input        stype;
        begin
            snoop_addr = addr;
            snoop_type = stype;
            snoop_req  = 1;
            @(posedge clk);   // controller processes snoop on this edge
            snoop_req  = 0;
            // Capture before next edge clears defaults
            cap_snoop_hit   = snoop_hit;
            cap_snoop_dirty = snoop_dirty;
            cap_link_push   = link_push_req;
            @(posedge clk);   // advance — outputs now cleared
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        pass_count = 0; fail_count = 0;
        $dumpfile("tb_L1_CC.vcd");
        $dumpvars(0, tb_L1_CC);

        // =====================================================================
        // TC1: Read miss — I → IS_D → S
        //   Address 0x0000_1000:  tag=0x001  index=0x00  offset=0
        // =====================================================================
        $display("\n── TC1: Read miss (I → S) ──");
        reset_dut;

        cpu_addr = 32'h0000_1000;
        cpu_we   = 0;
        cpu_request;
        check(cpu_stall, 1,      "TC1: stall on read miss");
        check(bus_req,   1,      "TC1: bus_req asserted");
        check(bus_we,    0,      "TC1: bus_we=0 (GetS)");

        bus_complete(128'hDEAD_BEEF_CAFE_1234_DEAD_BEEF_CAFE_5678);
        check(cpu_stall,          0,       "TC1: stall cleared after fill");
        check(dut.states[8'h00],  1,       "TC1: index 0x00 state=S");
        check(dut.tags[8'h00],    20'h001, "TC1: index 0x00 tag=0x001");

        // =====================================================================
        // TC2: Read hit — S, no stall
        // =====================================================================
        $display("\n── TC2: Read hit (S) ──");
        cpu_addr = 32'h0000_1000;
        cpu_we   = 0;
        cpu_request;
        check(cpu_stall, 0, "TC2: no stall on S read hit");
        check(bus_req,   0, "TC2: no bus_req on S read hit");
        @(posedge clk);

        // =====================================================================
        // TC3: Write miss — I → IM_D → M
        //   Address 0x0000_2000:  tag=0x002  index=0x20  offset=0
        // =====================================================================
        $display("\n── TC3: Write miss (I → M) ──");
        cpu_addr  = 32'h0000_2000;
        cpu_we    = 1;
        cpu_wdata = 32'hAABBCCDD;
        cpu_request;
        check(cpu_stall,          1,            "TC3: stall on write miss");
        check(bus_req,            1,            "TC3: bus_req for GetM");
        check(bus_we,             1,            "TC3: bus_we=1 (GetM)");
        check(dut.saved_cpu_addr, 32'h0000_2000,"TC3: saved_cpu_addr=0x2000");

        bus_complete(128'h0);
        check(cpu_stall,          0,       "TC3: stall cleared after GetM");
        check(dut.states[8'h20],  2,       "TC3: index 0x20 state=M");
        check(dut.tags[8'h20],    20'h002, "TC3: index 0x20 tag=0x002");
        @(posedge clk);

        // =====================================================================
        // TC4: Write hit — M, no stall
        // =====================================================================
        $display("\n── TC4: Write hit (M) ──");
        cpu_addr  = 32'h0000_2000;
        cpu_we    = 1;
        cpu_wdata = 32'h11223344;
        cpu_request;
        check(cpu_stall, 0, "TC4: no stall on M write hit");
        check(bus_req,   0, "TC4: no bus_req on M write hit");
        @(posedge clk);

        // =====================================================================
        // TC5: Write hit in S — S → SM_D → M
        //   Index 0x00 is in S with tag 0x001 from TC1
        // =====================================================================
        $display("\n── TC5: Write hit in S (S → M upgrade) ──");
        check(dut.states[8'h00], 1,       "TC5: precondition index 0x00=S");
        check(dut.tags[8'h00],   20'h001, "TC5: precondition tag=0x001");

        cpu_addr  = 32'h0000_1000;
        cpu_we    = 1;
        cpu_wdata = 32'hFFFFFFFF;
        cpu_request;
        check(cpu_stall,         1, "TC5: stall for S→M upgrade");
        check(bus_req,           1, "TC5: bus_req for upgrade");
        check(bus_we,            1, "TC5: bus_we=1 (GetM upgrade)");
        check(dut.states[8'h00], 5, "TC5: index 0x00 state=SM_D");

        bus_complete(128'h0);
        check(cpu_stall,         0, "TC5: stall cleared after upgrade");
        check(dut.states[8'h00], 2, "TC5: index 0x00 state=M");
        @(posedge clk);

        // =====================================================================
        // TC6: Dirty eviction before read
        //   Index 0x20 is M with tag 0x002 (from TC3/TC4).
        //   New address 0x0001_2000: same index 0x20, new tag 0x012.
        //   Phase 1: PutM eviction of old dirty line
        //   Phase 2: GetS fetch of new line
        // =====================================================================
        $display("\n── TC6: Dirty eviction before read ──");
        check(dut.states[8'h20], 2,       "TC6: precondition index 0x20=M");
        check(dut.tags[8'h20],   20'h002, "TC6: precondition tag=0x002");

        cpu_addr = 32'h0001_2000;
        cpu_we   = 0;
        cpu_request;
        // Phase 1 checks — eviction address must be the OLD dirty line
        check(cpu_stall,           1,       "TC6: stall on eviction");
        check(bus_req,             1,       "TC6: bus_req for PutM");
        check(bus_we,              1,       "TC6: bus_we=1 for PutM");
        check(bus_addr[31:12],     20'h002, "TC6: evict tag=0x002");
        check(bus_addr[11:4],      8'h20,   "TC6: evict index=0x20");
        check(dut.evict_active,    1,       "TC6: evict_active=1");

        bus_complete(128'h0); // eviction ack
        // Phase 2 checks — GetS for new address
        check(bus_req,          1, "TC6: bus_req for GetS");
        check(bus_we,           0, "TC6: bus_we=0 for GetS");
        check(dut.evict_active, 0, "TC6: evict_active cleared");

        bus_complete(128'hCAFE_BABE_1234_5678_CAFE_BABE_9ABC_DEF0);
        check(cpu_stall,          0,       "TC6: stall cleared after fill");
        check(dut.states[8'h20],  1,       "TC6: index 0x20 state=S");
        check(dut.tags[8'h20],    20'h012, "TC6: index 0x20 tag=0x012");
        @(posedge clk);

        // =====================================================================
        // TC7: Snoop GetS on M block — M → S, dirty data forwarded
        //   Index 0x00 is M with tag 0x001 from TC5
        // =====================================================================
        $display("\n── TC7: Snoop GetS on M block (M → S) ──");
        check(dut.states[8'h00], 2,       "TC7: precondition index 0x00=M");
        check(dut.tags[8'h00],   20'h001, "TC7: precondition tag=0x001");

        do_snoop(32'h0000_1000, 0); // GetS
        check(cap_snoop_hit,     1, "TC7: snoop_hit=1");
        check(cap_snoop_dirty,   1, "TC7: snoop_dirty=1 (was M)");
        check(cap_link_push,     1, "TC7: link_push_req=1 (C2C forward)");
        check(dut.states[8'h00], 1, "TC7: index 0x00 downgraded to S");

        // Read in S should hit with no stall
        cpu_addr = 32'h0000_1000;
        cpu_we   = 0;
        cpu_request;
        check(cpu_stall, 0, "TC7: post-snoop read hits S (no stall)");
        @(posedge clk);

        // =====================================================================
        // TC8: Snoop GetM on M block — M → I
        //   Upgrade index 0x00 back to M first, then snoop it
        // =====================================================================
        $display("\n── TC8: Snoop GetM on M block (M → I) ──");
        cpu_addr  = 32'h0000_1000;
        cpu_we    = 1;
        cpu_wdata = 32'hABCD1234;
        cpu_request;
        if (cpu_stall) begin
            check(dut.states[8'h00], 5, "TC8: setup SM_D");
            bus_complete(128'h0);
            check(cpu_stall, 0, "TC8: setup upgrade done");
        end
        check(dut.states[8'h00], 2, "TC8: precondition index 0x00=M");
        @(posedge clk);

        do_snoop(32'h0000_1000, 1); // GetM
        check(cap_snoop_hit,     1, "TC8: snoop_hit=1");
        check(cap_snoop_dirty,   1, "TC8: snoop_dirty=1 (was M)");
        check(dut.states[8'h00], 0, "TC8: index 0x00 invalidated (M→I)");

        cpu_addr = 32'h0000_1000;
        cpu_we   = 0;
        cpu_request;
        check(cpu_stall, 1, "TC8: post-GetM snoop read misses");
        bus_complete(128'h0);
        check(cpu_stall, 0, "TC8: cleanup stall cleared");
        @(posedge clk);

        // =====================================================================
        // TC9: Snoop GetM on S block — S → I
        //   Use fresh address 0x0000_3000: tag=0x003 index=0x30
        // =====================================================================
        $display("\n── TC9: Snoop GetM on S block (S → I) ──");
        cpu_addr = 32'h0000_3000;
        cpu_we   = 0;
        cpu_request;
        check(cpu_stall, 1, "TC9: setup read miss");
        bus_complete(128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111);
        check(cpu_stall,         0,       "TC9: setup fill done");
        check(dut.states[8'h30], 1,       "TC9: precondition index 0x30=S");
        check(dut.tags[8'h30],   20'h003, "TC9: precondition tag=0x003");
        @(posedge clk);

        do_snoop(32'h0000_3000, 1); // GetM
        check(cap_snoop_hit,     1, "TC9: snoop_hit=1");
        check(cap_snoop_dirty,   0, "TC9: snoop_dirty=0 (S is clean)");
        check(dut.states[8'h30], 0, "TC9: index 0x30 invalidated (S→I)");

        cpu_addr = 32'h0000_3000;
        cpu_we   = 0;
        cpu_request;
        check(cpu_stall, 1, "TC9: post-GetM snoop read misses");
        bus_complete(128'h0);
        check(cpu_stall, 0, "TC9: cleanup stall cleared");
        @(posedge clk);

        // =====================================================================
        // TC10: Snoop miss — address never cached
        //   0xDEAD_BEEF → index=0xBE, never populated.
        //   cpu_addr is set to 0 (also cold) to catch any bug where the
        //   controller checks req_index instead of snp_index.
        // =====================================================================
        $display("\n── TC10: Snoop miss ──");
        cpu_addr = 32'h0000_0000; // req_index=0x00, deliberately different
        check(dut.states[8'hBE], 0, "TC10: precondition index 0xBE=I");

        do_snoop(32'hDEAD_BEEF, 0);
        check(cap_snoop_hit,   0, "TC10: snoop_hit=0 on cold miss");
        check(cap_snoop_dirty, 0, "TC10: snoop_dirty=0 on cold miss");

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n══════════════════════════════════");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("══════════════════════════════════\n");
        $finish;
    end

    // ── Watchdog ─────────────────────────────────────────────────────────────
    initial begin
        #100000;
        $display("TIMEOUT: simulation exceeded 100us");
        $finish;
    end

endmodule
