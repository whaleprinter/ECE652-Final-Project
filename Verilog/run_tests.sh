#!/bin/bash

# Ensure output directories exist
mkdir -p Object_files
mkdir -p Hex_files

# Create a dummy hex file for Core 1 so it does nothing during these tests
touch Hex_files/dummy_c1.hex

run_test() {
    local c_file=$1
    local expected=$2
    local base_name=$(basename "$c_file" .c)
    local hex_file="Hex_files/${base_name}.hex"

    echo "======================================"
    echo "Running Test: $base_name"

    # 1. Compile C to Hex (Notice the updated C_programs/ and Object_files/ paths!)
    riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -ffreestanding -nostdlib -T link.ld boot_c0.s C_programs/$c_file -o Object_files/${base_name}.elf
    riscv64-unknown-elf-objcopy -O verilog Object_files/${base_name}.elf $hex_file

    # 2. Compile the Verilog simulation (ADDED -g2012 FLAG HERE!)
    iverilog -g2012 -D C0_FILE=\"$hex_file\" -D C1_FILE=\"Hex_files/dummy_c1.hex\" autotester_tb.v module_top.v L1_CC.v bus_arbiter.v L1D_cache.v L2_cache.v L1I_cache.v warp_v_core_mul.sv -o sim.vvp

    # 3. Run simulation and capture output
    output=$(vvp sim.vvp | grep "AUTOTEST_")

    # 4. Check the result
    if [[ $output == *"AUTOTEST_RESULT: $expected"* ]]; then
        echo "PASS (Got $expected)"
    elif [[ $output == *"TIMEOUT"* ]]; then
        echo "FAIL (Simulation Timed Out)"
    else
        echo "FAIL (Expected $expected, Output: $output)"
    fi
}

# Execute the Test Suite!
run_test "test_sum.c"    "150"
run_test "test_fact.c"   "3628800"

echo "======================================"
echo "Test Suite Complete."