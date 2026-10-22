`timescale 1ns / 1ps

// Self-checking system testbench.
//  - Each core signals completion either by writing 1 to x30 (result in x31), or by
//    writing its exit code to the sync unit's EXIT register (the C runtime does this).
//  - Expected results are passed as plusargs: +C0_EXPECT=<n> +C1_EXPECT=<n>
//  - +TIMEOUT=<cycles> overrides the default timeout
//  - Every idle bus cycle (unless +NO_INVARIANTS), the coherence invariants are checked:
//      SWMR:       a block is never M in one L1 while valid in the other
//      Data-value: a block held in S matches the copy in L2
//  - Coverage: every L1 state transition, every snoop type x local state, and key
//    protocol events are counted and printed as "COV ..." lines at the end

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

    localparam I    = 3'd0;
    localparam S    = 3'd1;
    localparam M    = 3'd2;
    localparam IS_D = 3'd3;
    localparam IM_D = 3'd4;
    localparam SM_D = 3'd5;

    reg [31:0] c0_expect, c1_expect;
    reg c0_done = 0, c1_done = 0;
    reg check_invariants;
    integer errors = 0;
    integer cycles = 0;
    integer timeout;
    reg x30_done;               // x30 == 1 means done (off with +EXIT_ONLY: compiled code uses x30 freely)
    integer i;

    initial begin
        if (!$value$plusargs("C0_EXPECT=%d", c0_expect)) c0_expect = 0;
        if (!$value$plusargs("C1_EXPECT=%d", c1_expect)) c1_expect = 0;
        check_invariants = !$test$plusargs("NO_INVARIANTS");
        if (!$value$plusargs("TIMEOUT=%d", timeout)) timeout = `TIMEOUT_CYCLES;
        x30_done = !$test$plusargs("EXIT_ONLY");
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

    // ---------------------------------------------------------------
    // Coverage
    // ---------------------------------------------------------------
    integer cov_tr  [0:63];     // [old*8 + new], both cores summed
    integer cov_snp [0:15];     // [type*8 + local state of the snooped block]
    integer cov_putm, cov_putm_cancel, cov_wb_gets, cov_fwd_gets, cov_fwd_getm;
    integer cov_both_req, cov_fill_link, cov_fill_l2, cov_upgrade_done;
    reg [2:0] prev0 [0:255];
    reg [2:0] prev1 [0:255];
    integer k;

    initial begin
        for (k = 0; k < 64; k = k + 1) cov_tr[k] = 0;
        for (k = 0; k < 16; k = k + 1) cov_snp[k] = 0;
        for (k = 0; k < 256; k = k + 1) begin prev0[k] = I; prev1[k] = I; end
        cov_putm = 0; cov_putm_cancel = 0; cov_wb_gets = 0; cov_fwd_gets = 0; cov_fwd_getm = 0;
        cov_both_req = 0; cov_fill_link = 0; cov_fill_l2 = 0; cov_upgrade_done = 0;
    end

    // State of the snooped block in the snooped L1 (I if the line holds another block)
    function [2:0] snoop_class(input [2:0] st, input tag_eq, input pending_same);
        snoop_class = (st == S || st == M) ? (tag_eq ? st : I) :
                      (st == I)             ? I : (pending_same ? st : I);
    endfunction

    `define COV_SNOOP(L1) \
        if (L1.snoop_req) begin \
            cov_snp[L1.snoop_type*8 + snoop_class(L1.states[L1.snp_index], \
                    L1.tags[L1.snp_index] == L1.snp_tag, \
                    L1.saved_cpu_addr[31:4] == L1.snoop_addr[31:4])] = \
            cov_snp[L1.snoop_type*8 + snoop_class(L1.states[L1.snp_index], \
                    L1.tags[L1.snp_index] == L1.snp_tag, \
                    L1.saved_cpu_addr[31:4] == L1.snoop_addr[31:4])] + 1; \
            if (L1.evict_active && L1.snoop_dirty && L1.snp_index == L1.saved_cpu_addr[11:4]) \
                cov_putm_cancel = cov_putm_cancel + 1; \
        end \
        if (L1.bus_ready && !L1.evict_active) begin \
            if (L1.is_fill && L1.link_push_valid) cov_fill_link = cov_fill_link + 1; \
            else if (L1.is_fill)                 cov_fill_l2   = cov_fill_l2 + 1; \
            else                                 cov_upgrade_done = cov_upgrade_done + 1; \
        end

    always @(posedge clk) begin
        if (!reset) begin
            `COV_SNOOP(dut.core0_l1)
            `COV_SNOOP(dut.core1_l1)
            if (dut.arbiter.state == 0 && dut.c0_bus_req && dut.c1_bus_req) cov_both_req = cov_both_req + 1;
            if (dut.arbiter.state == 0 && ((dut.c0_bus_req && dut.c0_bus_put && (!dut.c1_bus_req || dut.arbiter.core_priority == 0)) ||
                                           (dut.c1_bus_req && dut.c1_bus_put && !(dut.c0_bus_req && dut.arbiter.core_priority == 0))))
                cov_putm = cov_putm + 1;
            if (dut.arbiter.state == 4) cov_wb_gets = cov_wb_gets + 1;
            if ((dut.arbiter.state == 1 && dut.c1_snoop_dirty) || (dut.arbiter.state == 2 && dut.c0_snoop_dirty)) begin
                if (dut.arbiter.req_we) cov_fwd_getm = cov_fwd_getm + 1;
                else                    cov_fwd_gets = cov_fwd_gets + 1;
            end
        end
    end

    // Transitions: compare against last cycle's copy of each state array
    always @(negedge clk) begin
        if (!reset) begin
            for (k = 0; k < 256; k = k + 1) begin
                if (dut.core0_l1.states[k] !== prev0[k]) begin
                    cov_tr[prev0[k]*8 + dut.core0_l1.states[k]] = cov_tr[prev0[k]*8 + dut.core0_l1.states[k]] + 1;
                    prev0[k] = dut.core0_l1.states[k];
                end
                if (dut.core1_l1.states[k] !== prev1[k]) begin
                    cov_tr[prev1[k]*8 + dut.core1_l1.states[k]] = cov_tr[prev1[k]*8 + dut.core1_l1.states[k]] + 1;
                    prev1[k] = dut.core1_l1.states[k];
                end
            end
        end
    end

    function [8*4-1:0] st_name(input [2:0] st);
        case (st)
            I: st_name = "I"; S: st_name = "S"; M: st_name = "M";
            IS_D: st_name = "IS_D"; IM_D: st_name = "IM_D"; SM_D: st_name = "SM_D";
            default: st_name = "?";
        endcase
    endfunction

    task print_coverage;
        integer a, b;
        begin
            for (a = 0; a < 6; a = a + 1)
                for (b = 0; b < 6; b = b + 1)
                    if (cov_tr[a*8 + b] != 0)
                        $display("COV transition %0s->%0s %0d", st_name(a), st_name(b), cov_tr[a*8 + b]);
            for (a = 0; a < 2; a = a + 1)
                for (b = 0; b < 6; b = b + 1)
                    if (cov_snp[a*8 + b] != 0)
                        $display("COV snoop %0s@%0s %0d", a ? "GetM" : "GetS", st_name(b), cov_snp[a*8 + b]);
            $display("COV event putm %0d", cov_putm);
            $display("COV event putm_cancelled_by_snoop %0d", cov_putm_cancel);
            $display("COV event forward_on_GetS %0d", cov_fwd_gets);
            $display("COV event forward_on_GetM %0d", cov_fwd_getm);
            $display("COV event writeback_after_GetS_forward %0d", cov_wb_gets);
            $display("COV event fill_from_link %0d", cov_fill_link);
            $display("COV event fill_from_L2 %0d", cov_fill_l2);
            $display("COV event upgrade_without_data %0d", cov_upgrade_done);
            $display("COV event both_cores_request_same_cycle %0d", cov_both_req);
        end
    endtask

    always @(posedge clk) begin
        cycles <= cycles + 1;

        if (!reset && !c0_done && dut.sync.exited[0]) begin
            c0_done = 1;
            $display("C0 done at cycle %0d: exit code = %0d (expected %0d)", cycles, dut.sync.c0_exit_code, c0_expect);
            if (dut.sync.c0_exit_code !== c0_expect) errors = errors + 1;
        end
        if (!reset && !c1_done && dut.sync.exited[1]) begin
            c1_done = 1;
            $display("C1 done at cycle %0d: exit code = %0d (expected %0d)", cycles, dut.sync.c1_exit_code, c1_expect);
            if (dut.sync.c1_exit_code !== c1_expect) errors = errors + 1;
        end
        if (!reset && x30_done && c0_r30 == 1 && !c0_done) begin
            c0_done = 1;
            $display("C0 done at cycle %0d: x31 = %0d (expected %0d), x29 = %0d", cycles, c0_r31, c0_expect, dut.c0_r29);
            if (c0_r31 !== c0_expect) errors = errors + 1;
        end
        if (!reset && x30_done && c1_r30 == 1 && !c1_done) begin
            c1_done = 1;
            $display("C1 done at cycle %0d: x31 = %0d (expected %0d), x29 = %0d", cycles, c1_r31, c1_expect, dut.c1_r29);
            if (c1_r31 !== c1_expect) errors = errors + 1;
        end

        if (c0_done && c1_done) begin
            print_coverage;
            if (errors == 0) $display("TEST_PASS");
            else             $display("TEST_FAIL (%0d errors)", errors);
            $finish;
        end

        if (cycles > timeout) begin
            print_coverage;
            $display("TEST_FAIL (timeout: c0_done=%0d c1_done=%0d)", c0_done, c1_done);
            $finish;
        end
    end
endmodule
