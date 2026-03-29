\m5_TLV_version 1d --inlineGen --bestsv --noline --hdl verilog --clkEnable: tl-x.org
\SV
   // 1. MANUALLY DEFINE THE MODULE AND EXTERNAL PORTS
   module warp_v_core (
       input wire clk,
       input wire reset,
       
       // Data Memory Ports (For your MSI Cache)
       output wire [31:0] dmem_addr_out,
       output wire [31:0] dmem_wdata_out,
       output wire dmem_we_out,
       output wire dmem_req_out,
       input  wire [31:0] dmem_rdata_in,
       input  wire dmem_stall_in,
       
       // Instruction Memory Ports (NEW)
       output wire [31:0] imem_addr_out,
       output wire imem_req_out,
       input  wire [31:0] imem_rdata_in,
       input  wire imem_stall_in
   );

   // Dummy wires to satisfy Makerchip
   wire [31:0] cyc_cnt = 32'b0;
   wire passed;
   wire failed;
   wire [319:0] RW_rand_vect = 320'b0;

\m5
   use(m5-1.0)
   var(ISA, RISCV)
   var(EXT_M, 0)
   var(EXT_F, 0)
   var(DMEM_STYLE, EXTERNAL)
   
   // Combine stalls: CPU freezes if EITHER the D-Cache or I-Cache misses
   var(cpu_blocked, dmem_stall_in || imem_stall_in)
   
   var(EXTRA_REPLAY_BUBBLE, 0)
   var(EXTRA_PRED_TAKEN_BUBBLE, 0)
   var(EXTRA_JUMP_BUBBLE, 0)
   var(EXTRA_BRANCH_BUBBLE, 0)
   var(EXTRA_INDIRECT_JUMP_BUBBLE, 0)
   var(EXTRA_NON_PIPELINED_BUBBLE, 1)
   var(EXTRA_TRAP_BUBBLE, 1)
   var(NEXT_PC_STAGE, 0)
   var(FETCH_STAGE, 0)
   var(DECODE_STAGE, 0)
   var(BRANCH_PRED_STAGE, 0)
   var(REG_RD_STAGE, 0)
   var(EXECUTE_STAGE, 0)
   var(RESULT_STAGE, 0)
   var(REG_WR_STAGE, 0)
   var(MEM_WR_STAGE, 0)
   var(LD_RETURN_ALIGN, 1)
\SV
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v/71d9a9a9c02e692731b196dec4ca4811a41f0234/warp-v.tlv'])

\TLV
   m5+warpv_top()
   
   // THE RTL BYPASS
   |fetch
      @0
         // --- INSTRUCTION MEMORY BYPASS ---
         *imem_addr_out = /instr$Pc;
         *imem_req_out = ! /instr$reset;
         
         /instr
            // Override the internal fetch logic with our external port
            $raw[31:0] = *imem_rdata_in;

            // --- DATA MEMORY BYPASS ---
            *dmem_we_out = $valid_st;
            *dmem_req_out = $valid_st || $spec_ld;
            ?$ld_st_cond
               *dmem_addr_out = $addr;
            ?$st_cond
               *dmem_wdata_out = $st_value;
            ?$spec_ld
               $ld_data[31:0] = *dmem_rdata_in;
\SV
   endmodule