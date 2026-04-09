#!/bin/bash
iverilog -g2012 -o multicore_system.vvp L1D_cache.v L1I_cache.v L1_CC.v L2_cache.v tb_system.v bus_arbiter.v module_top.v warp_v_core_mul.sv ./sv_url_inc/picorv32_pcpi_div.sv ./sv_url_inc/picorv32_pcpi_fast_mul.sv

vvp multicore_system.vvp

gtkwave system_waves.vcd