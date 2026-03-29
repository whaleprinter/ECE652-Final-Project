`timescale 1ns / 1ps

module tb_L1I_cache();

    // Inputs
    reg clk;
    reg reset;
    reg [31:0] address;

    // Outputs
    wire [31:0] data;

    // Instantiate the Unit Under Test (UUT)
    L1I_cache uut (
        .clk(clk),
        .reset(reset),
        .address(address),
        .data(data)
    );

    // Clock generation (10ns period -> 100MHz)
    always #5 clk = ~clk;

    initial begin
        // Setup waveform dumping for GTKWave
        $dumpfile("icache_waves.vcd");
        $dumpvars(0, tb_L1I_cache);

        // Initialize Inputs
        clk = 0;
        reset = 1;
        address = 0;

        // Release reset after 15ns (on the negative edge to avoid race conditions)
        #15 reset = 0;

        // --- Test Sequence ---
        
        // Test 1: Read address 0x00 (Word 0)
        @(negedge clk);
        address = 32'h0000_0000;
        
        // Test 2: Read address 0x04 (Word 1)
        @(negedge clk);
        address = 32'h0000_0004;

        // Test 3: Read address 0x08 (Word 2)
        @(negedge clk);
        address = 32'h0000_0008;

        // Test 4: Jump to a higher address 0x10 (Word 4)
        @(negedge clk);
        address = 32'd12;

        // Test 5: Check boundary / unaligned edge case (though PC shouldn't normally do this)
        // If address is 0x05, address[11:2] still evaluates to 1 (Word 1).
        @(negedge clk);
        address = 32'd16;

        // Wait a couple of clocks and finish
        repeat(2) @(negedge clk);
        $display("Simulation Complete.");
        $finish;
    end

endmodule