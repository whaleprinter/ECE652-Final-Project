#!/bin/bash
set -e

mkdir -p Object_files
mkdir -p Hex_files


echo "Compiling Core 0 (MatMul Top)..."
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -ffreestanding -nostdlib -T link.ld Assembly_files/boot_c0.s C_programs/matmul_c0.c -o Object_files/matmul_c0.elf
riscv64-unknown-elf-objcopy -O verilog Object_files/matmul_c0.elf Hex_files/matmul_c0.hex

echo "Compiling Core 1 (MatMul Bottom)..."
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -ffreestanding -nostdlib -T link.ld Assembly_files/boot_c1.s C_programs/matmul_c1.c -o Object_files/matmul_c1.elf
riscv64-unknown-elf-objcopy -O verilog Object_files/matmul_c1.elf Hex_files/matmul_c1.hex

echo "Running Dual-Core MatMul Simulation..."
iverilog -g2012 -o sim.vvp autotester_tb.v module_top.v L1_CC.v bus_arbiter.v L1D_cache.v L2_cache.v L1I_cache.v warp_v_core_mul.sv ./sv_url_inc/picorv32_pcpi_div.sv ./sv_url_inc/picorv32_pcpi_fast_mul.sv


echo "TEST RESULTS:"
output=$(vvp sim.vvp)


if [[ $output == *"AUTOTEST_C0_RESULT: 72"* ]]; then
    echo "Core 0 (Top Half): PASS (Checksum 72)"
else
    echo "Core 0: FAIL"
    echo "$output"
fi


if [[ $output == *"AUTOTEST_C1_RESULT: 200"* ]]; then
    echo "Core 1 (Bottom Half): PASS (Checksum 200)"
else
    echo "Core 1: FAIL"
    echo "$output"
fi