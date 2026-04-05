`timescale 1ns / 1ps

module tb_bus_arbiter();

    // ==========================================
    // TB REGISTERS (Inputs to Arbiter)
    // ==========================================
    reg clk, reset;
    
    // Core 0
    reg          c0_bus_req;
    reg  [31:0]  c0_bus_addr;
    reg          c0_bus_we;
    reg  [127:0] c0_bus_wdata;
    reg          c0_snoop_hit;
    reg          c0_snoop_dirty;
    
    // Core 1
    reg          c1_bus_req;
    reg  [31:0]  c1_bus_addr;
    reg          c1_bus_we;
    reg  [127:0] c1_bus_wdata;
    reg          c1_snoop_hit;
    reg          c1_snoop_dirty;

    // L2 Cache
    reg  [127:0] l2_rdata;
    reg          l2_ready;

    // ==========================================
    // TB WIRES (Outputs from Arbiter)
    // ==========================================
    wire         c0_bus_grant;
    wire [127:0] c0_bus_rdata;
    wire         c0_bus_ready;
    wire         c0_snoop_req;
    wire [31:0]  c0_snoop_addr;
    wire         c0_snoop_type;
    
    wire         c1_bus_grant;
    wire [127:0] c1_bus_rdata;
    wire         c1_bus_ready;
    wire         c1_snoop_req;
    wire [31:0]  c1_snoop_addr;
    wire         c1_snoop_type;

    wire         l2_req;
    wire [31:0]  l2_addr;
    wire         l2_we;
    wire [127:0] l2_wdata;

    // ==========================================
    // INSTANTIATE UNIT UNDER TEST (UUT)
    // ==========================================
    bus_arbiter uut (
        .clk(clk), .reset(reset),
        
        // Core 0
        .c0_bus_req(c0_bus_req), .c0_bus_addr(c0_bus_addr), .c0_bus_we(c0_bus_we),
        .c0_bus_grant(c0_bus_grant), .c0_bus_rdata(c0_bus_rdata), .c0_bus_wdata(c0_bus_wdata), .c0_bus_ready(c0_bus_ready),
        .c0_snoop_req(c0_snoop_req), .c0_snoop_addr(c0_snoop_addr), .c0_snoop_type(c0_snoop_type),
        .c0_snoop_hit(c0_snoop_hit), .c0_snoop_dirty(c0_snoop_dirty),
        
        // Core 1
        .c1_bus_req(c1_bus_req), .c1_bus_addr(c1_bus_addr), .c1_bus_we(c1_bus_we),
        .c1_bus_grant(c1_bus_grant), .c1_bus_rdata(c1_bus_rdata), .c1_bus_wdata(c1_bus_wdata), .c1_bus_ready(c1_bus_ready),
        .c1_snoop_req(c1_snoop_req), .c1_snoop_addr(c1_snoop_addr), .c1_snoop_type(c1_snoop_type),
        .c1_snoop_hit(c1_snoop_hit), .c1_snoop_dirty(c1_snoop_dirty),

        // L2 Memory
        .l2_req(l2_req), .l2_addr(l2_addr), .l2_we(l2_we), .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata), .l2_ready(l2_ready)
    );

    // Clock generation (10ns period)
    always #5 clk = ~clk;

    initial begin
        // Setup for GTKWave
        $dumpfile("arbiter_waves.vcd");
        $dumpvars(0, tb_bus_arbiter);

        // Initialize Inputs
        clk = 0; reset = 1;
        c0_bus_req = 0; c0_bus_addr = 0; c0_bus_we = 0; c0_bus_wdata = 0; c0_snoop_hit = 0; c0_snoop_dirty = 0;
        c1_bus_req = 0; c1_bus_addr = 0; c1_bus_we = 0; c1_bus_wdata = 0; c1_snoop_hit = 0; c1_snoop_dirty = 0;
        l2_rdata = 0; l2_ready = 0;

        // Wait and release reset
        repeat(3) @(negedge clk);
        reset = 0;
        
        // ==========================================
        // SCENARIO 1: Core 0 requests (Clean L2 Fetch)
        // ==========================================
        $display("\n--- SCENARIO 1: Core 0 L2 Fetch ---");
        @(negedge clk);
        c0_bus_req = 1;
        c0_bus_addr = 32'hAAAA_BBBB;
        
        // Wait for Arbiter to snoop Core 1
        wait(c1_snoop_req);
        @(negedge clk);
        c0_bus_req = 0; // Drop request once granted
        c1_snoop_dirty = 0; // Core 1 does NOT have dirty data

        // Arbiter should pivot to L2
        wait(l2_req);
        @(negedge clk);
        // Simulate L2 memory responding
        l2_ready = 1;
        l2_rdata = 128'h1111_2222_3333_4444;
        
        @(negedge clk);
        l2_ready = 0;
        wait(c0_bus_ready); // Wait for arbiter to pass data back to C0
        $display("Scenario 1 Complete.");

        // ==========================================
        // SCENARIO 2: Core 1 requests (Dirty Snoop, C2C Bypass)
        // ==========================================
        $display("\n--- SCENARIO 2: Core 1 C2C Fetch (Bypass L2) ---");
        repeat(2) @(negedge clk);
        c1_bus_req = 1;
        c1_bus_addr = 32'hDEAD_BEEF;
        
        wait(c0_snoop_req);
        @(negedge clk);
        c1_bus_req = 0; 
        
        // Simulate Core 0 telling the arbiter it has dirty data!
        c0_snoop_dirty = 1; 
        
        @(negedge clk);
        c0_snoop_dirty = 0;
        
        // Arbiter should instantly trigger c1_bus_ready without touching L2
        wait(c1_bus_ready);
        $display("Scenario 2 Complete.");

        // ==========================================
        // SCENARIO 3: Simultaneous Request (Collision!)
        // ==========================================
        $display("\n--- SCENARIO 3: Simultaneous Bus Request ---");
        repeat(2) @(negedge clk);
        c0_bus_req = 1; c0_bus_addr = 32'h1111_1111;
        c1_bus_req = 1; c1_bus_addr = 32'h2222_2222;
        
        // Arbiter uses Round-Robin priority. Wait to see who it snoops.
        @(negedge clk);
        if (c1_snoop_req) begin
            $display("Core 0 won priority.");
            c0_bus_req = 0;
            c1_snoop_dirty = 0;
            wait(l2_req);
            @(negedge clk); l2_ready = 1; l2_rdata = 128'hAAAA;
            @(negedge clk); l2_ready = 0;
            wait(c0_bus_ready);
            
            // Now Arbiter should immediately pivot to waiting Core 1
            $display("Serving Core 1 next...");
            wait(c0_snoop_req);
            @(negedge clk);
            c1_bus_req = 0;
            c0_snoop_dirty = 0;
            wait(l2_req);
            @(negedge clk); l2_ready = 1; l2_rdata = 128'hBBBB;
            @(negedge clk); l2_ready = 0;
            wait(c1_bus_ready);
        end else begin
            $display("Core 1 won priority.");
            c1_bus_req = 0;
            c0_snoop_dirty = 0;
            wait(l2_req);
            @(negedge clk); l2_ready = 1; l2_rdata = 128'hBBBB;
            @(negedge clk); l2_ready = 0;
            wait(c1_bus_ready);
            
            // Now Arbiter should immediately pivot to waiting Core 0
            $display("Serving Core 0 next...");
            wait(c1_snoop_req);
            @(negedge clk);
            c0_bus_req = 0;
            c1_snoop_dirty = 0;
            wait(l2_req);
            @(negedge clk); l2_ready = 1; l2_rdata = 128'hAAAA;
            @(negedge clk); l2_ready = 0;
            wait(c0_bus_ready);
        end

        repeat(4) @(negedge clk);
        $display("\nSimulation Complete.");
        $finish;
    end
endmodule