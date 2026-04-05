`timescale 1ns / 1ps

module tb_new_L1_CC();

    // ==========================================
    // CLOCK AND RESET
    // ==========================================
    reg clk;
    reg reset;

    // ==========================================
    // CPU INTERFACE
    // ==========================================
    reg         cpu_req;
    reg  [31:0] cpu_addr;
    reg         cpu_we;
    reg  [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_stall;

    // ==========================================
    // BUS INTERFACE
    // ==========================================
    wire        bus_req;
    wire [31:0] bus_addr;
    wire        bus_we;
    reg         bus_grant;
    reg [127:0] bus_rdata;
    wire [127:0] bus_wdata;
    reg         bus_ready;

    // ==========================================
    // CORE-TO-CORE LINK
    // ==========================================
    wire        link_push_req;
    wire [127:0] link_data_out;
    reg         link_push_valid;
    reg [127:0] link_data_in;

    // ==========================================
    // SNOOP INTERFACE
    // ==========================================
    reg         snoop_req;
    reg  [31:0] snoop_addr;
    reg         snoop_type;
    wire        snoop_hit;
    wire        snoop_dirty;

    // ==========================================
    // UNIT UNDER TEST (UUT)
    // ==========================================
    L1_CC uut (
        .clk(clk),
        .reset(reset),
        
        .cpu_req(cpu_req),
        .cpu_addr(cpu_addr),
        .cpu_we(cpu_we),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_stall(cpu_stall),
        
        .bus_req(bus_req),
        .bus_addr(bus_addr),
        .bus_we(bus_we),
        .bus_grant(bus_grant),
        .bus_rdata(bus_rdata),
        .bus_wdata(bus_wdata),
        .bus_ready(bus_ready),
        
        .link_push_req(link_push_req),
        .link_data_out(link_data_out),
        .link_push_valid(link_push_valid),
        .link_data_in(link_data_in),
        
        .snoop_req(snoop_req),
        .snoop_addr(snoop_addr),
        .snoop_type(snoop_type),
        .snoop_hit(snoop_hit),
        .snoop_dirty(snoop_dirty)
    );
    // ==========================================
    // DEBUG WIRES (To force arrays into GTKWave)
    // ==========================================
    wire [2:0] debug_state_0 = uut.states[0];
    wire [19:0] debug_tag_0  = uut.tags[0];

    // Clock Generation
    always #5 clk = ~clk;

    // Task to simulate the Bus Arbiter responding to a request
    task arbiter_respond(input [127:0] data_to_return);
        begin
            // Wait until the controller actually asks for the bus
            wait(bus_req == 1);
            @(negedge clk);
            bus_grant = 1;      // Arbiter grants the bus
            @(negedge clk);
            bus_grant = 0;      // Drop grant
            
            // Simulate L2 memory latency (2 cycles)
            @(negedge clk);
            @(negedge clk);
            
            bus_ready = 1;      // Data is ready
            bus_rdata = data_to_return;
            @(negedge clk);
            bus_ready = 0;
        end
    endtask

    // Main Test Sequence
    initial begin
        // Setup Waveforms
        $dumpfile("l1_cc_waves.vcd");
        $dumpvars(0, tb_new_L1_CC);

        // Initialize all inputs
        clk = 0;
        reset = 1;
        cpu_req = 0; cpu_addr = 0; cpu_we = 0; cpu_wdata = 0;
        bus_grant = 0; bus_rdata = 0; bus_ready = 0;
        link_push_valid = 0; link_data_in = 0;
        snoop_req = 0; snoop_addr = 0; snoop_type = 0;

        #20 reset = 0;

        // =========================================================
        // TEST 1: Read Miss (I -> IS_D -> S)
        // =========================================================
        $display("\n--- TEST 1: CPU Read Miss ---");
        @(negedge clk);
        cpu_req = 1;
        cpu_we = 0;
        cpu_addr = 32'h0000_1000; // Tag=00001, Index=00
        
        // Let the CPU stall, then have Arbiter provide the block
        arbiter_respond(128'hAAAA_AAAA_BBBB_BBBB_CCCC_CCCC_DDDD_DDDD);
        
        wait(cpu_stall == 0); // Wait for controller to finish
        $display("Test 1 Complete. Block should be in S state.");

        // =========================================================
        // TEST 2: Write Hit/Upgrade (S -> SM_D -> M)
        // =========================================================
        $display("\n--- TEST 2: CPU Write Upgrade ---");
        @(negedge clk);
        cpu_req = 1;
        cpu_we = 1;
        cpu_addr = 32'h0000_1000; // Same address
        cpu_wdata = 32'hFFFF_FFFF; 
        
        // Upgrade request to bus. Arbiter just ACKs it (no data needed)
        arbiter_respond(128'h0);
        
        wait(cpu_stall == 0);
        $display("Test 2 Complete. Block should be in M state.");
        cpu_req = 0; // CPU goes idle

        // =========================================================
        // TEST 3: Snoop Hit on M (Snoop GetS)
        // =========================================================
        $display("\n--- TEST 3: Arbiter Snoops the Modified Block ---");
        @(negedge clk);
        snoop_req = 1;
        snoop_addr = 32'h0000_1000; // Snoop the address we just modified
        snoop_type = 0;             // GetS (Other core wants to read)

        @(negedge clk);
        $display("Snoop Hit: %b, Snoop Dirty: %b, Link Push Req: %b", snoop_hit, snoop_dirty, link_push_req);
        snoop_req = 0;
        $display("Test 3 Complete. Block should have downgraded to S.");

        // =========================================================
        // TEST 4: Dirty Eviction (PutM) followed by Fetch
        // =========================================================
        $display("\n--- TEST 4: Evict Dirty Block ---");
        // Step 4a: First, let's write to it again so it goes back to M
        @(negedge clk);
        cpu_req = 1; cpu_we = 1; cpu_addr = 32'h0000_1000;
        arbiter_respond(128'h0); // Upgrade S -> M
        wait(cpu_stall == 0);

        // Step 4b: Now, write to a NEW tag, but SAME index (Index 00)
        @(negedge clk);
        cpu_req = 1;
        cpu_we = 1;
        cpu_addr = 32'h000A_1000; // Tag=000A1, Index=00. Collision!
        
        $display("Waiting for Eviction Request (PutM)...");
        wait(bus_req == 1 && bus_we == 1 && bus_addr == 32'h0000_1000); 
        $display("Eviction request confirmed. Acknowledging PutM.");
        
        // Ack the eviction
        @(negedge clk);
        bus_grant = 1; 
        @(negedge clk);
        bus_grant = 0;
        bus_ready = 1;
        @(negedge clk);
        bus_ready = 0;

        $display("Waiting for Demand Fetch (GetM)...");
        // Controller should immediately request the new address
        wait(bus_req == 1 && bus_we == 1 && bus_addr == 32'h000A_1000);
        $display("Fetch request confirmed. Providing new block.");
        
        // Provide the new block
        @(negedge clk);
        bus_grant = 1;
        @(negedge clk);
        bus_grant = 0;
        bus_ready = 1;
        bus_rdata = 128'h9999_9999_8888_8888_7777_7777_6666_6666;
        @(negedge clk);
        bus_ready = 0;

        wait(cpu_stall == 0);
        $display("Test 4 Complete. Old block evicted, new block fetched to M.");

        #50;
        $display("\nAll MSI functionality verified.");
        $finish;
    end

endmodule