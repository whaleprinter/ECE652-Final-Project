#!/bin/bash

# Check if a filename was provided
if [ -z "$1" ]; then
    echo "Error: No filename provided."
    echo "Usage: ./compile_s.sh <filename_without_extension>"
    echo "Example: ./compile_s.sh boot"
    exit 1
fi

BASENAME=$1

echo "Translating Assembly_files/${BASENAME}.s..."

# 1. Assemble to Object file (placed in Object_files directory)
riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o Object_files/${BASENAME}.o Assembly_files/${BASENAME}.s

# Check if the assembly was successful
if [ $? -ne 0 ]; then
    echo "Assembly failed!"
    exit 1
fi

# 2. Extract Verilog Hex format from the Object file
riscv64-unknown-elf-objcopy -O verilog Object_files/${BASENAME}.o Hex_files/${BASENAME}.hex

echo "Success! Created Hex_files/${BASENAME}.hex"