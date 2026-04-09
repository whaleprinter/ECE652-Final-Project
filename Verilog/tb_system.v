`timescale 1ns / 1ps

module tb_system();
    reg clk;
    reg reset;


    system_top uut (
        .clk(clk),
        .reset(reset)
    );

    // 100 MHz Clock
    always #5 clk = ~clk;

    initial begin

        $dumpfile("system_waves.vcd");
        $dumpvars(0, tb_system);


        // Power on
        clk = 0;
        reset = 1;

        // Hold reset for 10 full clock cycles (Deep Flush)
        // We use negedge to avoid clock-edge race conditions
        repeat(10) @(negedge clk); 
        
        // Release reset cleanly
        reset = 0; 
        $display("System Booting... Cores are executing firmware.");

        // Let it run
        #3000;

        
        $display("Simulation Complete.");
        $finish;
    end
endmodule