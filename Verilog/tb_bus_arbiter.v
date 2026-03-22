`timescale 1ns / 1ps

module tb_bus_arbiter();

    // Inputs to the arbiter (Registers in the TB)
    reg clk, reset;
    
    reg C0_request, C0_write_enable;
    reg [31:0] C0_address;
    reg C0_L1_ready, C0_L1_hit, C0_L1_dirty;
    
    reg C1_request, C1_write_enable;
    reg [31:0] C1_address;
    reg C1_L1_ready, C1_L1_hit, C1_L1_dirty;

    // Outputs from the arbiter (Wires in the TB)
    wire C0_ready, C0_stall, C0_check_L1;
    wire [31:0] C0_L1_address;
    
    wire C1_ready, C1_stall, C1_check_L1;
    wire [31:0] C1_L1_address;

    // Instantiate the Unit Under Test (UUT)
    bus_arbiter uut (
        .clk(clk), .reset(reset),
        
        .C0_request(C0_request), .C0_address(C0_address), .C0_write_enable(C0_write_enable),
        .C0_ready(C0_ready), .C0_stall(C0_stall),
        .C0_check_L1(C0_check_L1), .C0_L1_address(C0_L1_address),
        .C0_L1_ready(C0_L1_ready), .C0_L1_hit(C0_L1_hit), .C0_L1_dirty(C0_L1_dirty),
        
        .C1_request(C1_request), .C1_address(C1_address), .C1_write_enable(C1_write_enable),
        .C1_ready(C1_ready), .C1_stall(C1_stall),
        .C1_check_L1(C1_check_L1), .C1_L1_address(C1_L1_address),
        .C1_L1_ready(C1_L1_ready), .C1_L1_hit(C1_L1_hit), .C1_L1_dirty(C1_L1_dirty)
    );

    // Clock generation (10ns period)
    always #5 clk = ~clk;

    initial begin
        // Setup for GTKWave
        $dumpfile("arbiter_waves.vcd");
        $dumpvars(0, tb_bus_arbiter);

        // Initialize Inputs
        clk = 0; reset = 1;
        C0_request = 0; C0_address = 0; C0_write_enable = 0; C0_L1_ready = 0; C0_L1_hit = 0; C0_L1_dirty = 0;
        C1_request = 0; C1_address = 0; C1_write_enable = 0; C1_L1_ready = 0; C1_L1_hit = 0; C1_L1_dirty = 0;

        // Wait a few clocks, then release reset on a falling edge
        repeat(3) @(negedge clk);
        reset = 0;
        
        // ==========================================
        // SCENARIO 1: Core 0 requests the bus
        // ==========================================
        @(negedge clk);
        C0_request = 1;
        C0_address = 32'hAAAA_BBBB;
        
        // Let it stall in SERVE_C0 for a couple of clock cycles
        repeat(2) @(negedge clk);
        C1_L1_ready = 1; // Core 1 finishes snoop
        
        // De-assert request once granted
        @(negedge clk);
        C0_request = 0;
        C1_L1_ready = 0;

        // ==========================================
        // SCENARIO 2: Core 1 requests the bus
        // ==========================================
        repeat(2) @(negedge clk);
        C1_request = 1;
        C1_address = 32'hDEAD_BEEF;
        
        repeat(2) @(negedge clk);
        C0_L1_ready = 1; // Core 0 finishes snooping
        
        @(negedge clk);
        C1_request = 0;
        C0_L1_ready = 0;

        // ==========================================
        // SCENARIO 3: Simultaneous Request (Collision!)
        // ==========================================
        repeat(2) @(negedge clk);
        C0_request = 1; C0_address = 32'h1111_1111;
        C1_request = 1; C1_address = 32'h2222_2222;
        
        // Let arbiter pick the winner based on priority
        repeat(2) @(negedge clk);
        C1_L1_ready = 1; // Assume C0 won, C1 finishes snoop
        
        @(negedge clk);
        C0_request = 0; // C0 is happy, drops request
        C1_L1_ready = 0;
        
        // Arbiter should pivot to serve C1
        repeat(2) @(negedge clk);
        C0_L1_ready = 1; // C0 finishes snoop
        
        @(negedge clk);
        C1_request = 0; // C1 is happy
        C0_L1_ready = 0;

        repeat(4) @(negedge clk);
        $display("Simulation Complete.");
        $finish;
    end
endmodule