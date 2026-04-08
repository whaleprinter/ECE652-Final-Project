#!/bin/bash

# Check if a filename was provided
if [ -z "$1" ]; then
    echo "Error: No filename provided."
    echo "Usage: ./compile_c.sh <filename_without_extension>"
    echo "Example: ./compile_c.sh test"
    exit 1
fi

BASENAME=$1

echo "Compiling C_programs/${BASENAME}.c..."

# 1. Compile C to ELF (placed in Object_files directory)
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O1 -nostdlib -nostartfiles -Ttext 0x00000000 -o Object_files/${BASENAME}.elf C_programs/${BASENAME}.c

# Check if the compile was successful
if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

# 2. Extract Verilog Hex format from the ELF in Object_files
riscv64-unknown-elf-objcopy -O verilog Object_files/${BASENAME}.elf Hex_files/${BASENAME}.hex

echo "Success! Created Hex_files/${BASENAME}.hex"