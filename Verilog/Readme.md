*To compile C down to RISC-V Binary:*
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O1 -nostdlib -nostartfiles -Ttext 0x00000000 -o test.elf test.c
riscv64-unknown-elf-objcopy -O verilog test.elf L1I_cache_init.hex

*To compile C down to RISC-V Assembly:*
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -S test.s test.c

*To translate .s RISC-V assembly to RISC-V Binary:*
riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o test.o test.s
riscv64-unknown-elf-objcopy -O binary test.o program.bin // For binary
riscv64-unknown-elf-objcopy -O verilog test.o program.hex // For hex

*To compile everything:*
iverilog -g2012 -o multicore_system.vvp L1D_cache.v L1I_cache.v L1_CC.v L2_cache.v bus_arbiter.v module_top.v warp_v_core_mul.sv ./sv_url_inc/picorv32_pcpi_div.sv ./sv_url_inc/picorv32_pcpi_fast_mul.sv

*To autocompile/translate:*
chmod +x compile_c.sh
chmod +x compile_s.sh

./compile_c.sh my_program // (my_program.c)
./compile_s.sh my_program // (my_program.s)

*To run the regression suite (needs iverilog, python3, and riscv64-unknown-elf-gcc):*
./tests/run_all.sh                 // everything
./tests/run_all.sh upgrade_race    // one test

Each test runs on `tests/tb_coherence.v`, which checks the coherence invariants
(single-writer/multiple-reader and S copies matching L2) on every idle bus cycle,
plus each core's result in x31 once it writes 1 to x30. Directed tests live in
`tests/asm/`; `tests/gen_random.py` generates the seeded random stress tests.
