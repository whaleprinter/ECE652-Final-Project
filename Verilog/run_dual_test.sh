#!/bin/bash
set -e 


mkdir -p Object_files
mkdir -p Hex_files


echo "Compiling Core 0 (Sum)..."
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -ffreestanding -nostdlib -T link.ld Assembly_files/boot_c0.s C_programs/test_sum.c -o Object_files/test_sum.elf
riscv64-unknown-elf-objcopy -O verilog Object_files/test_sum.elf Hex_files/test_sum.hex

echo "Compiling Core 1 (Factorial)..."
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -ffreestanding -nostdlib -T link.ld Assembly_files/boot_c1.s C_programs/test_fact.c -o Object_files/test_fact.elf
riscv64-unknown-elf-objcopy -O verilog Object_files/test_fact.elf Hex_files/test_fact.hex

echo "Running Dual-Core Simulation..."

iverilog -g2012 -o sim.vvp autotester_tb.v module_top.v L1_CC.v bus_arbiter.v L1D_cache.v L2_cache.v L1I_cache.v warp_v_core_mul.sv ./sv_url_inc/picorv32_pcpi_div.sv ./sv_url_inc/picorv32_pcpi_fast_mul.sv


echo "TEST RESULTS:"

vvp sim.vvp
