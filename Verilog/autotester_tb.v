module autotester_tb;
    reg clk;
    reg reset;


    wire [31:0] c0_r30, c0_r31;
    wire [31:0] c1_r30, c1_r31;

    system_top dut (
        .clk(clk),
        .reset(reset),
        .c0_r30(c0_r30), .c0_r31(c0_r31),
        .c1_r30(c1_r30), .c1_r31(c1_r31)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        reset = 1;
        #20 reset = 0;
    end

    // Track completion
    reg c0_done = 0;
    reg c1_done = 0;

    always @(posedge clk) begin

        if (c0_r30 == 1 && !c0_done) begin
            $display("AUTOTEST_C0_RESULT: %0d", c0_r31);
            c0_done = 1;
        end

        if (c1_r30 == 1 && !c1_done) begin
            $display("AUTOTEST_C1_RESULT: %0d", c1_r31);
            c1_done = 1;
        end


        if (c0_done && c1_done) begin
            $finish;
        end
    end


    initial begin
        #100000; 
        $display("AUTOTEST_ERROR: TIMEOUT");
        $finish;
    end
endmodule