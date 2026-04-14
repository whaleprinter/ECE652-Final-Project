module system_top (
    input wire clk,
    input wire reset,

    output wire [31:0] c0_r1,
    output wire [31:0] c0_r2,
    output wire [31:0] c0_r3,
    output wire [31:0] c0_r4,
    output wire [31:0] c0_r5,
    output wire [31:0] c0_r6,
    output wire [31:0] c0_r7,
    output wire [31:0] c0_r8,
    output wire [31:0] c0_r9,
    output wire [31:0] c0_r10,
    output wire [31:0] c0_r11,
    output wire [31:0] c0_r12,
    output wire [31:0] c0_r13,
    output wire [31:0] c0_r14,
    output wire [31:0] c0_r15,
    output wire [31:0] c0_r16,
    output wire [31:0] c0_r17,
    output wire [31:0] c0_r18,
    output wire [31:0] c0_r19,
    output wire [31:0] c0_r20,
    output wire [31:0] c0_r21,
    output wire [31:0] c0_r22,
    output wire [31:0] c0_r23,
    output wire [31:0] c0_r24,
    output wire [31:0] c0_r25,
    output wire [31:0] c0_r26,
    output wire [31:0] c0_r27,
    output wire [31:0] c0_r28,
    output wire [31:0] c0_r29,
    output wire [31:0] c0_r30,
    output wire [31:0] c0_r31,


    output wire [31:0] c1_r1,
    output wire [31:0] c1_r2,
    output wire [31:0] c1_r3,
    output wire [31:0] c1_r4,
    output wire [31:0] c1_r5,
    output wire [31:0] c1_r6,
    output wire [31:0] c1_r7,
    output wire [31:0] c1_r8,
    output wire [31:0] c1_r9,
    output wire [31:0] c1_r10,
    output wire [31:0] c1_r11,
    output wire [31:0] c1_r12,
    output wire [31:0] c1_r13,
    output wire [31:0] c1_r14,
    output wire [31:0] c1_r15,
    output wire [31:0] c1_r16,
    output wire [31:0] c1_r17,
    output wire [31:0] c1_r18,
    output wire [31:0] c1_r19,
    output wire [31:0] c1_r20,
    output wire [31:0] c1_r21,
    output wire [31:0] c1_r22,
    output wire [31:0] c1_r23,
    output wire [31:0] c1_r24,
    output wire [31:0] c1_r25,
    output wire [31:0] c1_r26,
    output wire [31:0] c1_r27,
    output wire [31:0] c1_r28,
    output wire [31:0] c1_r29,
    output wire [31:0] c1_r30,
    output wire [31:0] c1_r31
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
    
    // // Core 0 Register outputs
    // wire [31:0] c0_r1, c0_r2, c0_r3, c0_r4, c0_r5, c0_r6, c0_r7, c0_r8, c0_r9;
    // wire [31:0] c0_r10, c0_r11, c0_r12, c0_r13, c0_r14, c0_r15, c0_r16, c0_r17;
    // wire [31:0] c0_r18, c0_r19, c0_r20, c0_r21, c0_r22, c0_r23, c0_r24, c0_r25;
    // wire [31:0] c0_r26, c0_r27, c0_r28, c0_r29, c0_r30, c0_r31;

    
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
        .link_push_valid(c1_link_push_req),   
        .link_data_in(c1_link_data_out),      
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
        .link_push_valid(c0_link_push_req),   
        .link_data_in(c0_link_data_out),      
        // Snoop Interface
        .snoop_req(c1_snoop_req),
        .snoop_addr(c1_snoop_addr),
        .snoop_type(c1_snoop_type),
        .snoop_hit(c1_snoop_hit),
        .snoop_dirty(c1_snoop_dirty)
    );


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


    L2_cache main_memory (
        .clk(clk),
        .reset(reset),
        .req(l2_req),
        .addr(l2_addr),
        .we(l2_we),
        .wdata(l2_wdata),
        .rdata(l2_rdata),
        .ready(l2_ready)
    );

    L1I_cache #(
        .INIT_FILE("Hex_files/matmul_c0.hex") // Update file for Core 0
    ) core0_l1i (
        .clk(clk),
        .reset(reset),
        .address(c0_imem_addr),
        .data(c0_imem_rdata)
    );

    L1I_cache #(
        .INIT_FILE("Hex_files/matmul_c1.hex") // Update file for Core 1
    ) core1_l1i (
        .clk(clk),
        .reset(reset),
        .address(c1_imem_addr),
        .data(c1_imem_rdata)
    );

    warp_v_core core0 (
        .clk(clk),
        .reset(reset),
        
        .dmem_rdata_in(c0_rdata),
        .dmem_stall_in(c0_stall), 
        
        .dmem_addr_out(c0_addr),
        .dmem_wdata_out(c0_wdata),
        .dmem_we_out(c0_we),
        .dmem_req_out(c0_req),

        .imem_rdata_in(c0_imem_rdata),
        .imem_stall_in(1'b0), 
        
        .imem_addr_out(c0_imem_addr),
        .imem_req_out(c0_imem_req),

        // Core 0 Registers:
        .x1_ra(c0_r1), 
        .x2_sp(c0_r2), 
        .x3_gp(c0_r3), 
        .x4_tp(c0_r4), 
        .x5_t0(c0_r5), 
        .x6_t1(c0_r6), 
        .x7_t2(c0_r7), 
        .x8_s0(c0_r8),
        .x9_s1(c0_r9), 
        .x10_a0(c0_r10), 
        .x11_a1(c0_r11), 
        .x12_a2(c0_r12), 
        .x13_a3(c0_r13), 
        .x14_a4(c0_r14), 
        .x15_a5(c0_r15), 
        .x16_a6(c0_r16),
        .x17_a7(c0_r17), 
        .x18_s2(c0_r18), 
        .x19_s3(c0_r19), 
        .x20_s4(c0_r20), 
        .x21_s5(c0_r21), 
        .x22_s6(c0_r22), 
        .x23_s7(c0_r23), 
        .x24_s8(c0_r24),
        .x25_s9(c0_r25), 
        .x26_s10(c0_r26), 
        .x27_s11(c0_r27), 
        .x28_t3(c0_r28), 
        .x29_t4(c0_r29), 
        .x30_t5(c0_r30), 
        .x31_t6(c0_r31)


    );



    warp_v_core core1 (
        .clk(clk),
        .reset(reset),
        
        .dmem_rdata_in(c1_rdata),
        .dmem_stall_in(c1_stall),
        
        .dmem_addr_out(c1_addr),
        .dmem_wdata_out(c1_wdata),
        .dmem_we_out(c1_we),
        .dmem_req_out(c1_req),

        .imem_rdata_in(c1_imem_rdata),
        .imem_stall_in(1'b0), 
        
        .imem_addr_out(c1_imem_addr),
        .imem_req_out(c1_imem_req),

        // Core 1 Registers:
        .x1_ra(c1_r1), 
        .x2_sp(c1_r2), 
        .x3_gp(c1_r3), 
        .x4_tp(c1_r4), 
        .x5_t0(c1_r5), 
        .x6_t1(c1_r6), 
        .x7_t2(c1_r7), 
        .x8_s0(c1_r8),
        .x9_s1(c1_r9), 
        .x10_a0(c1_r10), 
        .x11_a1(c1_r11), 
        .x12_a2(c1_r12), 
        .x13_a3(c1_r13), 
        .x14_a4(c1_r14), 
        .x15_a5(c1_r15), 
        .x16_a6(c1_r16),
        .x17_a7(c1_r17), 
        .x18_s2(c1_r18), 
        .x19_s3(c1_r19), 
        .x20_s4(c1_r20), 
        .x21_s5(c1_r21), 
        .x22_s6(c1_r22), 
        .x23_s7(c1_r23), 
        .x24_s8(c1_r24),
        .x25_s9(c1_r25), 
        .x26_s10(c1_r26), 
        .x27_s11(c1_r27), 
        .x28_t3(c1_r28), 
        .x29_t4(c1_r29), 
        .x30_t5(c1_r30), 
        .x31_t6(c1_r31)


        
    );









endmodule