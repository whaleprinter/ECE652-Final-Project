`timescale 1ns / 1ps

module tb_L1D_cache();

    // Inputs
    reg clk;
    reg [7:0] index;
    reg [1:0] offset;
    reg [31:0] word_write_data;
    reg word_write_enable;
    reg ctrl_write_enable;
    reg [127:0] ctrl_write_data;

    // Outputs
    wire [31:0] word_read_data;
    wire [127:0] ctrl_read_data;

    // Instantiate the Unit Under Test (UUT)
    L1D_cache uut (
        .clk(clk),
        .index(index),
        .offset(offset),
        .word_write_data(word_write_data),
        .word_write_enable(word_write_enable),
        .word_read_data(word_read_data),
        .ctrl_write_enable(ctrl_write_enable),
        .ctrl_write_data(ctrl_write_data),
        .ctrl_read_data(ctrl_read_data)
    );

    // Clock generation (10ns period)
    always #5 clk = ~clk;

    initial begin
        $dumpfile("l1d_waves.vcd");
        $dumpvars(0, tb_L1D_cache);

        // Initialize Inputs
        clk = 0;
        index = 0;
        offset = 0;
        word_write_data = 0;
        word_write_enable = 0;
        ctrl_write_enable = 0;
        ctrl_write_data = 0;

        // Wait a few clocks for stable state
        #20;

        // =========================================================
        // TEST 1: Controller Block Write -> CPU Word Reads
        // =========================================================
        $display("--- Test 1: Controller Write, CPU Read ---");
        
        @(negedge clk);
        ctrl_write_enable = 1;
        index = 8'h0A; // Target Cache line 10
        // Write 4 distinct hex words so we can easily verify them visually
        ctrl_write_data = 128'hDDDDDDDD_CCCCCCCC_BBBBBBBB_AAAAAAAA;
        
        @(negedge clk);
        ctrl_write_enable = 0; 
        
        // Read Word 0
        offset = 2'b00; 
        @(negedge clk);
        $display("Read Offset 00: %h (Expected AAAAAAAA)", word_read_data);

        // Read Word 1
        offset = 2'b01; 
        @(negedge clk);
        $display("Read Offset 01: %h (Expected BBBBBBBB)", word_read_data);

        // Read Word 2
        offset = 2'b10; 
        @(negedge clk);
        $display("Read Offset 10: %h (Expected CCCCCCCC)", word_read_data);

        // Read Word 3
        offset = 2'b11; 
        @(negedge clk);
        $display("Read Offset 11: %h (Expected DDDDDDDD)", word_read_data);


        // =========================================================
        // TEST 2: CPU Word Writes -> Controller Block Read
        // =========================================================
        $display("\n--- Test 2: CPU Write, Controller Read ---");
        
        @(negedge clk);
        index = 8'h1F; // Target Cache line 31
        word_write_enable = 1;
        offset = 2'b00;
        word_write_data = 32'h11111111;

        @(negedge clk);
        offset = 2'b10; // Skip word 1, write word 2
        word_write_data = 32'h33333333;

        @(negedge clk);
        word_write_enable = 0;
        
        // The index is already set to 8'h1F from the lines above.
        // Let the synchronous read catch up for one more clock edge.
        @(negedge clk);
        $display("Ctrl Block Read: %h", ctrl_read_data);
        $display("(Expected:       xxxxxxxx_33333333_xxxxxxxx_11111111)"); 
        // Note: The unwritten words will be 'x' because we didn't zero out the array initially

        #20;
        $display("\nSimulation Complete.");
        $finish;
    end
endmodule