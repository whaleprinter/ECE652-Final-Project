module system_top (
    input wire clk,
    input wire reset
);

    // CPU 0 and L1
    wire        c0_req;
    wire [31:0] c0_addr;
    wire        c0_we;
    wire [31:0] c0_wdata;
    wire [31:0] c0_rdata;
    wire        c0_stall;

    // CPU 0 and L1I
    wire [31:0] c0_imem_addr;
    wire        c0_imem_req;
    wire [31:0] c0_imem_rdata;
    wire        c0_imem_stall;
    
    // L1 and Arbiter
    wire        c0_bus_req;
    wire [31:0] c0_bus_addr;
    wire        c0_bus_we;
    wire        c0_bus_grant;
    wire [127:0] c0_bus_rdata;
    wire [127:0] c0_bus_wdata;
    wire        c0_bus_ready;

    wire        c0_snoop_req;
    wire [31:0] c0_snoop_addr;
    wire        c0_snoop_type;
    wire        c0_snoop_hit;
    wire        c0_snoop_dirty;

    // C0 to C1 Link
    wire        c0_link_push_req;
    wire [127:0] c0_link_data_out;

    
    // CPU 1 and L1
    wire        c1_req;
    wire [31:0] c1_addr;
    wire        c1_we;
    wire [31:0] c1_wdata;
    wire [31:0] c1_rdata;
    wire        c1_stall;

    // CPU 1 and L1I
    wire [31:0] c1_imem_addr;
    wire        c1_imem_req;
    wire [31:0] c1_imem_rdata;
    wire        c1_imem_stall;

    // L1 and Arbiter
    wire        c1_bus_req;
    wire [31:0] c1_bus_addr;
    wire        c1_bus_we;
    wire        c1_bus_grant;
    wire [127:0] c1_bus_rdata;
    wire [127:0] c1_bus_wdata;
    wire        c1_bus_ready;

    wire        c1_snoop_req;
    wire [31:0] c1_snoop_addr;
    wire        c1_snoop_type;
    wire        c1_snoop_hit;
    wire        c1_snoop_dirty;

    // C1 to C0 Link
    wire        c1_link_push_req;
    wire [127:0] c1_link_data_out;

    // L2
    wire        l2_req;
    wire [31:0] l2_addr;
    wire        l2_we;
    wire [127:0] l2_wdata;
    wire [127:0] l2_rdata;
    wire        l2_ready;




    L1_CC core0_l1 (
        .clk(clk),
        .reset(reset),
        // CPU Interface
        .cpu_req(c0_req),
        .cpu_addr(c0_addr),
        .cpu_we(c0_we),
        .cpu_wdata(c0_wdata),
        .cpu_rdata(c0_rdata),
        .cpu_stall(c0_stall),
        // Bus Interface
        .bus_req(c0_bus_req),
        .bus_addr(c0_bus_addr),
        .bus_we(c0_bus_we),
        .bus_grant(c0_bus_grant),
        .bus_rdata(c0_bus_rdata),
        .bus_wdata(c0_bus_wdata),
        .bus_ready(c0_bus_ready),
        // Link
        .link_push_req(c0_link_push_req),
        .link_data_out(c0_link_data_out),
        .link_push_valid(c1_link_push_req),   // From Core 1
        .link_data_in(c1_link_data_out),      // From Core 1
        // Snoop Interface
        .snoop_req(c0_snoop_req),
        .snoop_addr(c0_snoop_addr),
        .snoop_type(c0_snoop_type),
        .snoop_hit(c0_snoop_hit),
        .snoop_dirty(c0_snoop_dirty)
    );


    L1_CC core1_l1 (
        .clk(clk),
        .reset(reset),
        // CPU Interface
        .cpu_req(c1_req),
        .cpu_addr(c1_addr),
        .cpu_we(c1_we),
        .cpu_wdata(c1_wdata),
        .cpu_rdata(c1_rdata),
        .cpu_stall(c1_stall),
        // Bus Interface
        .bus_req(c1_bus_req),
        .bus_addr(c1_bus_addr),
        .bus_we(c1_bus_we),
        .bus_grant(c1_bus_grant),
        .bus_rdata(c1_bus_rdata),
        .bus_wdata(c1_bus_wdata),
        .bus_ready(c1_bus_ready),
        // Link
        .link_push_req(c1_link_push_req),
        .link_data_out(c1_link_data_out),
        .link_push_valid(c0_link_push_req),   // From Core 0
        .link_data_in(c0_link_data_out),      // From Core 0
        // Snoop Interface
        .snoop_req(c1_snoop_req),
        .snoop_addr(c1_snoop_addr),
        .snoop_type(c1_snoop_type),
        .snoop_hit(c1_snoop_hit),
        .snoop_dirty(c1_snoop_dirty)
    );

    // --- BUS ARBITER ---
    bus_arbiter arbiter (
        .clk(clk),
        .reset(reset),
        // Core 0 Interconnect
        .c0_bus_req(c0_bus_req),
        .c0_bus_addr(c0_bus_addr),
        .c0_bus_we(c0_bus_we),
        .c0_bus_grant(c0_bus_grant),
        .c0_bus_rdata(c0_bus_rdata),
        .c0_bus_wdata(c0_bus_wdata),
        .c0_bus_ready(c0_bus_ready),
        .c0_snoop_req(c0_snoop_req),
        .c0_snoop_addr(c0_snoop_addr),
        .c0_snoop_type(c0_snoop_type),
        .c0_snoop_hit(c0_snoop_hit),
        .c0_snoop_dirty(c0_snoop_dirty),
        // Core 1 Interconnect
        .c1_bus_req(c1_bus_req),
        .c1_bus_addr(c1_bus_addr),
        .c1_bus_we(c1_bus_we),
        .c1_bus_grant(c1_bus_grant),
        .c1_bus_rdata(c1_bus_rdata),
        .c1_bus_wdata(c1_bus_wdata),
        .c1_bus_ready(c1_bus_ready),
        .c1_snoop_req(c1_snoop_req),
        .c1_snoop_addr(c1_snoop_addr),
        .c1_snoop_type(c1_snoop_type),
        .c1_snoop_hit(c1_snoop_hit),
        .c1_snoop_dirty(c1_snoop_dirty),
        // L2 Interconnect
        .l2_req(l2_req),
        .l2_addr(l2_addr),
        .l2_we(l2_we),
        .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata),
        .l2_ready(l2_ready)
    );

    // --- MAIN MEMORY (L2 CACHE) ---
    L2_cache main_memory (
        .clk(clk),
        .req(l2_req),
        .addr(l2_addr),
        .we(l2_we),
        .wdata(l2_wdata),
        .rdata(l2_rdata),
        .ready(l2_ready)
    );

    L1I_cache #(
        .INIT_FILE("core0_program.hex") 
    ) core0_l1i (
        .clk(clk),
        .reset(reset),
        // .address((core0.FETCH_Cnt_n1 - 1) * 4),
        .address(c0_imem_addr),
        .data(c0_imem_rdata)
    );

    L1I_cache #(
        .INIT_FILE("core1_program.hex") 
    ) core1_l1i (
        .clk(clk),
        .reset(reset),
        .address(c1_imem_addr),
        .data(c1_imem_rdata)
    );

    wire [31:0] dmem_addr_out, dmem_wdata_out, imem_addr_out;

    warp_v_core core0 (
        .clk(clk),
        .reset(reset),
        
        // Tie Data Memory to always return 0 and never stall
        .dmem_rdata_in(32'b0),
        .dmem_stall_in(1'b0),
        
        .dmem_addr_out(dmem_addr_out),
        .dmem_wdata_out(dmem_wdata_out),
        .dmem_we_out(dmem_we_out),
        .dmem_req_out(dmem_req_out),

        // Hardcode the Instruction Memory to always return NOP (addi x0, x0, 0)
        // and never stall.
        .imem_rdata_in(c0_imem_rdata),
        .imem_stall_in(1'b0),
        
        .imem_addr_out(c0_imem_addr),
        .imem_req_out(c0_imem_req)
    );








    // reg [31:0] c0_imem_rdata_reg;
    // reg        c0_imem_valid;

    // always @(posedge clk) begin
    //     if (reset) begin
    //         c0_imem_valid <= 0;
    //     end else begin
    //         if (c0_imem_req) begin
    //             c0_imem_rdata_reg <= c0_imem_rdata; // from L1I
    //             c0_imem_valid <= 1;
    //         end else begin
    //             c0_imem_valid <= 0;
    //         end
    //     end
    // end

// reg [3:0] reset_counter;

// always @(posedge clk) begin
//     if (reset)
//         reset_counter <= 0;
//     else if (reset_counter != 4'hF)
//         reset_counter <= reset_counter + 1;
// end

// wire init_done = (reset_counter == 4'hF);

    // warp_v_core uut (
    //     .clk(clk),
    //     .reset(reset),
        
    //     // Tie Data Memory to always return 0 and never stall
    //     .dmem_rdata_in(32'b0),
    //     .dmem_stall_in(1'b0),
        
    //     .dmem_addr_out(dmem_addr_out),
    //     .dmem_wdata_out(dmem_wdata_out),
    //     .dmem_we_out(dmem_we_out),
    //     .dmem_req_out(dmem_req_out),

    //     // Hardcode the Instruction Memory to always return NOP (addi x0, x0, 0)
    //     // and never stall.
    //     .imem_rdata_in(32'h00000013),
    //     .imem_stall_in(1'b0),
        
    //     .imem_addr_out(imem_addr_out),
    //     .imem_req_out(imem_req_out)
    // );

    // warp_v_core core0(
    //     .clk(clk),
    //     .reset(reset),
    //     .dmem_addr_out(c0_addr),
    //     .dmem_wdata_out(c0_wdata),
    //     .dmem_we_out(c0_we),
    //     .dmem_req_out(c0_req),
    //     .dmem_rdata_in(c0_rdata),
    //     .dmem_stall_in(c0_stall),
    //     .imem_addr_out(c0_imem_addr),
    //     .imem_req_out(c0_imem_req),
    //     .imem_rdata_in(32'h00000013), // DEBUG
    //     .imem_stall_in(1'b0) // DEBUG
    //     // .imem_rdata_in(c0_imem_req ? c0_imem_rdata : 32'b0), // Provide valid data only when request is active
    //     // .imem_stall_in(c0_stall)//reset ? 1'b1 : c0_stall)
    // );

//     always @(posedge clk) begin
//     if (c0_imem_req) begin
//         $display("PC=%h INSTR=%h", c0_imem_addr, c0_imem_rdata);
//     end
// end

// always @(posedge clk) begin
//     if (^c0_imem_addr === 1'bx)
//         $display("PC became X at time %t", $time);
// end

    // warp_v_core #(
    //     .INIT_FILE("basic_test.hex")
    // ) core1 (
    //     .clk(clk),
    //     .reset(reset),
    //     .dmem_addr_out(c1_addr),
    //     .dmem_wdata_out(c1_wdata),
    //     .dmem_we_out(c1_we),
    //     .dmem_req_out(c1_req),
    //     .dmem_rdata_in(c1_rdata),
    //     .dmem_stall_in(c1_stall)
        // .imem_addr_out(c1_imem_addr),
        // .imem_req_out(c1_imem_req),
        // .imem_rdata_in(c1_imem_req ? c1_imem_rdata : 32'b0),
        // .imem_stall_in(c1_stall)
    // );


endmodule