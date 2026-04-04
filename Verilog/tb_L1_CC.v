`timescale 1ns/1ps

// =============================================================================
//  tb_L1_CC.v  —  Testbench for L1 Cache Controller (MSI Snooping Protocol)
//
//  Tests:
//    TC1  – Read miss  (I → IS_D → S)
//    TC2  – Read hit   (S, no stall)
//    TC3  – Write miss (I → IM_D → M)
//    TC4  – Write hit  (M, no stall)
//    TC5  – Write hit  in S (S → SM_D → M, upgrade)
//    TC6  – Dirty eviction before read  (M → evict → IS_D → S)
//    TC7  – Snoop GetS on M block       (M → S, dirty data pushed)
//    TC8  – Snoop GetM on M block       (M → I)
//    TC9  – Snoop GetM on S block       (S → I)
//    TC10 – Snoop miss                  (no hit, no dirty)
// =============================================================================

module tb_L1_CC;

    // ── Clock / Reset ────────────────────────────────────────────────────────
    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ── DUT Ports ────────────────────────────────────────────────────────────
    // CPU interface
    reg         cpu_req;
    reg  [31:0] cpu_addr;
    reg         cpu_we;
    reg  [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_stall;

    // Main bus interface
    wire        bus_req;
    wire [31:0] bus_addr;
    wire        bus_we;
    reg         bus_grant;
    reg [127:0] bus_rdata;
    wire[127:0] bus_wdata;
    reg         bus_ready;

    // Core-to-core link
    wire        link_push_req;
    wire[127:0] link_data_out;
    reg         link_push_valid;
    reg [127:0] link_data_in;

    // Snoop interface
    reg         snoop_req;
    reg  [31:0] snoop_addr;
    reg         snoop_type;
    wire        snoop_hit;
    wire        snoop_dirty;

    // ── DUT Instantiation ────────────────────────────────────────────────────
    L1_CC dut (
        .clk(clk), .reset(reset),
        .cpu_req(cpu_req), .cpu_addr(cpu_addr),
        .cpu_we(cpu_we),   .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_stall(cpu_stall),
        .bus_req(bus_req),  .bus_addr(bus_addr),
        .bus_we(bus_we),    .bus_grant(bus_grant),
        .bus_rdata(bus_rdata), .bus_wdata(bus_wdata),
        .bus_ready(bus_ready),
        .link_push_req(link_push_req), .link_data_out(link_data_out),
        .link_push_valid(link_push_valid), .link_data_in(link_data_in),
        .snoop_req(snoop_req), .snoop_addr(snoop_addr),
        .snoop_type(snoop_type),
        .snoop_hit(snoop_hit), .snoop_dirty(snoop_dirty)
    );

    // ── Helpers ──────────────────────────────────────────────────────────────
    integer pass_count, fail_count;

    task reset_dut;
        begin
            reset = 1; cpu_req = 0; cpu_we = 0; cpu_addr = 0; cpu_wdata = 0;
            bus_grant = 0; bus_rdata = 0; bus_ready = 0;
            link_push_valid = 0; link_data_in = 0;
            snoop_req = 0; snoop_addr = 0; snoop_type = 0;
            @(posedge clk); @(posedge clk);
            reset = 0;
            @(posedge clk);
        end
    endtask

    // Grant bus access then signal completion one cycle later
    task bus_complete;
        input [127:0] rdata;
        begin
            // Grant bus
            @(posedge clk);
            bus_grant = 1;
            @(posedge clk);
            bus_grant = 0;
            // Simulate bus transaction latency (2 cycles)
            @(posedge clk); @(posedge clk);
            bus_rdata = rdata;
            bus_ready = 1;
            @(posedge clk);
            bus_ready = 0;
        end
    endtask

    task check(input [63:0] got, input [63:0] expected, input [127:0] name);
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

    // ── Test Cases ───────────────────────────────────────────────────────────
    initial begin
        pass_count = 0; fail_count = 0;
        $dumpfile("tb_L1_CC.vcd");
        $dumpvars(0, tb_L1_CC);

        // ===========================================================
        // TC1: Read miss — I → IS_D → S
        // Address 0x0000_1000: tag=0x1, index=0, offset=0
        // ===========================================================
        $display("\n── TC1: Read miss (I → S) ──");
        reset_dut;

        cpu_addr  = 32'h0000_1000;
        cpu_we    = 0;
        cpu_req   = 1;
        @(posedge clk);   // Controller sees miss, asserts stall + bus_req
        cpu_req   = 0;
        check(cpu_stall, 1, "       TC1: stall asserted on miss");
        check(bus_req,   1, "       TC1: bus_req asserted");
        check(bus_we,    0, "       TC1: bus_we=0 (GetS)");

        bus_complete(128'hDEAD_BEEF_CAFE_1234_DEAD_BEEF_CAFE_5678);

        @(posedge clk);
        check(cpu_stall, 0, "       TC1: stall deasserted after fill");

        // ===========================================================
        // TC2: Read hit — S, no stall
        // Same address, now in S state
        // ===========================================================
        $display("\n── TC2: Read hit (S) ──");
        cpu_addr  = 32'h0000_1000;
        cpu_we    = 0;
        cpu_req   = 1;
        @(posedge clk);
        cpu_req   = 0;
        check(cpu_stall, 0, "       TC2: no stall on S read hit");
        check(bus_req,   0, "       TC2: no bus_req on S read hit");

        // ===========================================================
        // TC3: Write miss — I → IM_D → M  (use a different address/index)
        // Address 0x0000_2000: index=0x10
        // ===========================================================
        $display("\n── TC3: Write miss (I → M) ──");
        cpu_addr  = 32'h0000_2000;
        cpu_we    = 1;
        cpu_wdata = 32'hAABBCCDD;
        cpu_req   = 1;
        @(posedge clk);
        cpu_req   = 0;
        @(posedge clk);
        check(cpu_stall, 1, "       TC3: stall on write miss");
        check(bus_req,   1, "       TC3: bus_req for GetM");
        check(bus_we,    1, "       TC3: bus_we=1 (GetM/upgrade)");

        bus_complete(128'h0);

        // After TC3's bus_complete, before TC4:
        $display("DEBUG after TC3: state[0]=%0d tag[0]=%0h state[0x20]=%0d tag[0x20]=%0h", dut.states[0], dut.tags[0], dut.states[8'h20], dut.tags[8'h20]);

        @(posedge clk);
        check(cpu_stall, 0, "       TC3: stall cleared after GetM");

        // ===========================================================
        // TC4: Write hit — M, no stall
        // Same address as TC3, now in M state
        // ===========================================================
        $display("\n── TC4: Write hit (M) ──");
        cpu_addr  = 32'h0000_2000;
        cpu_we    = 1;
        cpu_wdata = 32'h11223344;
        cpu_req   = 1;
        @(posedge clk);
        cpu_req   = 0;
        check(cpu_stall, 0, "       TC4: no stall on M write hit");
        check(bus_req,   0, "       TC4: no bus_req on M write hit");

        // ===========================================================
        // TC5: Write hit in S — upgrade S → SM_D → M
        // Address 0x0000_1000 is in S from TC1/TC2
        // ===========================================================
        $display("\n── TC5: Write hit in S (upgrade S → M) ──");
        cpu_addr  = 32'h0000_1000;
        cpu_we    = 1;
        cpu_wdata = 32'hFFFFFFFF;
        $display("DEBUG TC5 before: state[0]=%0d tag[0]=%0h req_tag=%0h tag_match=%0b", dut.states[0], dut.tags[0], 32'h0000_1000 >> 12, dut.tag_match);
        cpu_req = 1;
        @(posedge clk);
        cpu_req = 0;
        $display("DEBUG TC5 after edge: cpu_stall=%0b bus_req=%0b state[0]=%0d", cpu_stall, bus_req, dut.states[0]);
        check(cpu_stall, 1, "TC5: stall for S→M upgrade");
        check(bus_req,   1, "TC5: bus_req for upgrade");

        bus_complete(128'h0);
        @(posedge clk);
        check(cpu_stall, 0, "       TC5: stall cleared after upgrade");

        // ===========================================================
        // TC6: Dirty eviction before read
        // 0x0000_2000 is M. Now access 0x0001_2000 (same index, diff tag).
        // Expect: evict M first (bus_we=1, bus_addr=evict addr), then GetS.
        // ===========================================================
        $display("\n── TC6: Dirty eviction before read ──");
        cpu_addr  = 32'h0001_2000;   // same index 0x10, new tag
        cpu_we    = 0;
        cpu_req = 1;
        @(posedge clk);
        cpu_req = 0;
        // Check everything here, before bus_complete touches bus_addr
        check(cpu_stall,      1,    "TC6: stall on eviction");
        check(bus_req,        1,    "TC6: bus_req for eviction");
        check(bus_we,         1,    "TC6: bus_we=1 for PutM eviction");
        check(bus_addr[11:4], 8'h20,"TC6: evict addr index=0x20");

        // Eviction completes → controller issues GetS for new address
        bus_complete(128'h0);   // eviction ack
        @(posedge clk);
        check(bus_req, 1, "     TC6: bus_req for GetS after eviction");
        check(bus_we,  0, "     TC6: bus_we=0 for GetS");

        bus_complete(128'hCAFE_BABE_1234_5678_CAFE_BABE_9ABC_DEF0);
        @(posedge clk);
        check(cpu_stall, 0, "TC6: stall cleared after fill");

        // ===========================================================
        // TC7: Snoop GetS on M block → M→S, dirty data forwarded
        // 0x0000_1000 is M (from TC5 upgrade)
        // ===========================================================
        $display("\n── TC7: Snoop GetS on M block (M → S) ──");
        snoop_addr = 32'h0000_1000;
        snoop_type = 0;   // GetS
        $display("DEBUG TC7 before: state[0]=%0d tag[0]=%0h", dut.states[0], dut.tags[0]);
        snoop_req = 1;
        @(posedge clk);    // controller sees snoop_req=1, sets snoop_hit/dirty/link_push_req
        snoop_req = 0;
        // Check immediately — outputs valid right now, will clear next cycle
        $display("DEBUG TC7 after edge: snoop_hit=%0b snoop_dirty=%0b state[0]=%0d", snoop_hit, snoop_dirty, dut.states[0]);
        check(snoop_hit,     1, "TC7: snoop_hit=1");
        check(snoop_dirty,   1, "TC7: snoop_dirty=1 (was M)");
        check(link_push_req, 1, "TC7: link_push_req (C2C forward)");
        @(posedge clk);    // now advance before CPU read check
        // State should have moved to S — we can verify via a follow-up read
        // (no stall expected for a subsequent read)
        cpu_addr = 32'h0000_1000; cpu_we = 0; cpu_req = 1;
        @(posedge clk); cpu_req = 0;
        check(cpu_stall, 0, "       TC7: post-snoop read is S-hit (no stall)");

        // ===========================================================
        // TC8: Snoop GetM on M block → M→I, dirty data forwarded
        // Need to get 0x0000_1000 back to M first
        // ===========================================================
        $display("\n── TC8: Snoop GetM on M block (M → I) ──");
        // Upgrade to M via write
        cpu_addr = 32'h0000_1000; cpu_we = 1; cpu_wdata = 32'hABCD; cpu_req = 1;
        @(posedge clk); cpu_req = 0;
        if (cpu_stall) begin
            bus_complete(128'h0);
            @(posedge clk);
        end
        // Now snoop GetM
        snoop_addr = 32'h0000_1000;
        snoop_type = 1;   // GetM
        snoop_req  = 1;
        @(posedge clk);
        snoop_req  = 0;
        check(snoop_hit,   1, "     TC8: snoop_hit=1");
        check(snoop_dirty, 1, "     TC8: snoop_dirty=1");
        // State → I: follow-up read should miss
        cpu_addr = 32'h0000_1000; cpu_we = 0; cpu_req = 1;
        @(posedge clk); cpu_req = 0;
        check(cpu_stall, 1, "       TC8: post-GetM snoop causes miss (I state)");
        // Clean up stall
        bus_complete(128'h0);
        @(posedge clk);

        // ===========================================================
        // TC9: Snoop GetM on S block → S→I
        // Put 0x0000_3000 into S state first
        // ===========================================================
        $display("\n── TC9: Snoop GetM on S block (S → I) ──");
        cpu_addr = 32'h0000_3000; cpu_we = 0; cpu_req = 1;
        @(posedge clk); cpu_req = 0;
        bus_complete(128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111);
        @(posedge clk); // now S
        snoop_addr = 32'h0000_3000;
        snoop_type = 1; // GetM
        snoop_req  = 1;
        @(posedge clk); snoop_req = 0;
        check(snoop_hit,   1, "     TC9: snoop_hit=1 on S block");
        check(snoop_dirty, 0, "     TC9: snoop_dirty=0 (S is clean)");
        // Follow-up read should miss (I)
        cpu_addr = 32'h0000_3000; cpu_we = 0; cpu_req = 1;
        @(posedge clk); cpu_req = 0;
        check(cpu_stall, 1, "       TC9: post-GetM snoop causes miss (S→I)");
        bus_complete(128'h0);
        // end of TC9 snoop check  
        @(posedge clk); // let snoop_hit clear
        @(posedge clk); // extra margin
        $display("DEBUG between TC9/TC10: snoop_hit=%0b", snoop_hit);
        // now do TC10

        // ===========================================================
        // TC10: Snoop miss — address not in cache
        // ===========================================================
        // At the start of TC10:
        $display("DEBUG TC10: state[0xBE]=%0d tag[0xBE]=%0h", dut.states[8'hBE], dut.tags[8'hBE]);
        $display("\n── TC10: Snoop miss ──");
        snoop_addr = 32'hDEAD_BEEF;
        snoop_type = 0;
        snoop_req  = 1;
        @(posedge clk); snoop_req = 0;
        check(snoop_hit,   0, "     TC10: snoop_hit=0 on cold miss");
        check(snoop_dirty, 0, "     TC10: snoop_dirty=0 on cold miss");

        // ===========================================================
        // Summary
        // ===========================================================
        $display("\n══════════════════════════════════");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("══════════════════════════════════\n");
        $finish;
    end

    // ── Watchdog ─────────────────────────────────────────────────────────────
    initial begin
        #50000;
        $display("TIMEOUT: simulation exceeded 50us");
        $finish;
    end

endmodule
