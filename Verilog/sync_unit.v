// Memory-mapped synchronization unit (uncached I/O at 0x8000_0000).
//
// The WARP-V cores have no atomic instructions (no RV32A), so this block
// provides the primitives parallel programs need. Every access completes in
// the cycle it is issued, and accesses from both cores in the same cycle are
// applied core 0 first, then core 1, so each read-modify-write is atomic.
//
//   Offset  Name         Read                              Write
//   0x00    CORE_ID      id of the accessing core (0/1)    -
//   0x04    NUM_CORES    2                                 -
//   0x08    CYCLES       free-running cycle counter        -
//   0x10    PUTCHAR      -                                 print a character (simulation console)
//   0x14    EXIT         -                                 finish this core with the written exit code
//   0x20    BARRIER      current generation                arrive; when every core has arrived,
//                                                          the generation increments
//   0x40+4i LOCK[i]      0 = acquired (lock is now held),  release
//           i = 0..7     1 = already held by someone
//   0x60+4i COUNTER[i]   value, then increments by 1       set value
//           i = 0..3     (atomic fetch-and-add)
module sync_unit #(
    parameter NUM_CORES = 2
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        c0_req,
    input  wire        c0_we,
    input  wire  [7:0] c0_addr,
    input  wire [31:0] c0_wdata,
    output reg  [31:0] c0_rdata,

    input  wire        c1_req,
    input  wire        c1_we,
    input  wire  [7:0] c1_addr,
    input  wire [31:0] c1_wdata,
    output reg  [31:0] c1_rdata,

    output reg   [1:0] exited,        // Per-core: program finished
    output reg  [31:0] c0_exit_code,
    output reg  [31:0] c1_exit_code
);

    localparam CORE_ID   = 8'h00;
    localparam NCORES    = 8'h04;
    localparam CYCLES    = 8'h08;
    localparam PUTCHAR   = 8'h10;     // LOCK[i] = 0x40 + 4i, COUNTER[i] = 0x60 + 4i (decoded below)
    localparam EXIT      = 8'h14;
    localparam BARRIER   = 8'h20;

    reg  [31:0] cycles;
    reg   [7:0] locks;
    reg  [31:0] counters [0:3];
    reg  [31:0] barrier_gen;
    reg   [1:0] arrived;

    wire c0_rd = c0_req && !c0_we;
    wire c1_rd = c1_req && !c1_we;
    wire c0_wr = c0_req &&  c0_we;
    wire c1_wr = c1_req &&  c1_we;

    wire       c0_lock = c0_addr[7:5] == 3'b010;     // 0x40-0x5C
    wire       c1_lock = c1_addr[7:5] == 3'b010;
    wire [2:0] c0_lock_id = c0_addr[4:2];
    wire [2:0] c1_lock_id = c1_addr[4:2];
    wire       c0_ctr = c0_addr[7:4] == 4'h6;        // 0x60-0x6C
    wire       c1_ctr = c1_addr[7:4] == 4'h6;
    wire [1:0] c0_ctr_id = c0_addr[3:2];
    wire [1:0] c1_ctr_id = c1_addr[3:2];

    // Core 0 goes first, so core 1 sees core 0's effect from the same cycle
    wire c0_claims = c0_rd && c0_lock && !locks[c0_lock_id];
    wire c1_lock_held = locks[c1_lock_id] || (c0_claims && c0_lock_id == c1_lock_id);
    wire c0_bumps = c0_rd && c0_ctr;
    wire c0_sets  = c0_wr && c0_ctr;

    // Reads
    always @(*) begin
        case (c0_addr)
            CORE_ID: c0_rdata = 32'd0;
            NCORES:  c0_rdata = NUM_CORES;
            CYCLES:  c0_rdata = cycles;
            BARRIER: c0_rdata = barrier_gen;
            default: c0_rdata = c0_lock ? {31'b0, locks[c0_lock_id]} :
                                c0_ctr  ? counters[c0_ctr_id] : 32'b0;
        endcase
        case (c1_addr)
            CORE_ID: c1_rdata = 32'd1;
            NCORES:  c1_rdata = NUM_CORES;
            CYCLES:  c1_rdata = cycles;
            BARRIER: c1_rdata = barrier_gen;
            default: c1_rdata = c1_lock ? {31'b0, c1_lock_held} :
                                c1_ctr  ? ((c0_ctr_id == c1_ctr_id && c0_sets)  ? c0_wdata :
                                           (c0_ctr_id == c1_ctr_id && c0_bumps) ? counters[c1_ctr_id] + 1 :
                                                                                  counters[c1_ctr_id]) : 32'b0;
        endcase
    end

    wire [1:0] arrive_now = {c1_wr && c1_addr == BARRIER, c0_wr && c0_addr == BARRIER};

    // Side effects
    integer n;
    always @(posedge clk) begin
        if (reset) begin
            cycles <= 0;
            locks <= 0;
            barrier_gen <= 0;
            arrived <= 0;
            exited <= 0;
            c0_exit_code <= 0;
            c1_exit_code <= 0;
            for (n = 0; n < 4; n = n + 1) counters[n] <= 0;
        end else begin
            cycles <= cycles + 1;

            // Locks: release by write, acquire by read of a free lock
            if (c0_wr && c0_lock) locks[c0_lock_id] <= 1'b0;
            if (c0_claims)        locks[c0_lock_id] <= 1'b1;
            if (c1_wr && c1_lock) locks[c1_lock_id] <= 1'b0;
            if (c1_rd && c1_lock && !c1_lock_held) locks[c1_lock_id] <= 1'b1;

            // Counters: core 1's access is applied on top of core 0's
            for (n = 0; n < 4; n = n + 1) begin
                if (c1_wr && c1_ctr && c1_ctr_id == n[1:0])
                    counters[n] <= c1_wdata;
                else if (c1_rd && c1_ctr && c1_ctr_id == n[1:0])
                    counters[n] <= c1_rdata + 1;
                else if (c0_sets && c0_ctr_id == n[1:0])
                    counters[n] <= c0_wdata;
                else if (c0_bumps && c0_ctr_id == n[1:0])
                    counters[n] <= counters[n] + 1;
            end

            // Barrier: the last core to arrive opens the next generation
            if ((arrived | arrive_now) == 2'b11) begin
                arrived <= 2'b00;
                barrier_gen <= barrier_gen + 1;
            end else begin
                arrived <= arrived | arrive_now;
            end

            if (c0_wr && c0_addr == EXIT) begin exited[0] <= 1'b1; c0_exit_code <= c0_wdata; end
            if (c1_wr && c1_addr == EXIT) begin exited[1] <= 1'b1; c1_exit_code <= c1_wdata; end
        end
    end

`ifndef SYNTHESIS
    // Simulation console: one line buffer per core so output doesn't interleave mid-line
    reg [7:0] line [0:1][0:119];
    integer len [0:1];
    initial begin len[0] = 0; len[1] = 0; end

    task console_put(input integer core, input [7:0] ch);
        integer j;
        begin
            if (ch == 8'h0A || len[core] == 120) begin
                $write("[core %0d] ", core);
                for (j = 0; j < len[core]; j = j + 1) $write("%c", line[core][j]);
                $write("\n");
                len[core] = 0;
            end
            if (ch != 8'h0A) begin
                line[core][len[core]] = ch;
                len[core] = len[core] + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!reset && c0_wr && c0_addr == PUTCHAR) console_put(0, c0_wdata[7:0]);
        if (!reset && c1_wr && c1_addr == PUTCHAR) console_put(1, c1_wdata[7:0]);
    end
`endif

endmodule
