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


        clk = 0;
        reset = 1;


        #20;
        reset = 0;
        $display("Starting");

        #40000; // Adjust this value if longer time is needed for execution
        
        $display("Simulation Complete.");
        $finish;
    end
endmodule