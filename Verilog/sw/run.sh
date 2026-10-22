#!/bin/bash
# Builds and runs parallel C programs on the dual-core system.
#
# Usage (from anywhere):
#   ./sw/run.sh                 run every program in sw/programs and check exit codes
#   ./sw/run.sh hello matmul    run some of them
#   ./sw/run.sh --speedup       time the parallel kernels on 1 and 2 cores
#
# Each program runs on both cores (SPMD) with the invariant-checking
# testbench; it passes when both cores exit with code 0.

cd "$(dirname "$0")/.."

BUILD=sw/build
mkdir -p $BUILD
CC="riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -ffreestanding -Os -Wall -Isw -Wl,--no-warn-rwx-segments"
RTL="module_top.v L1_CC.v bus_arbiter.v L1D_cache.v L2_cache.v L1I_cache.v sync_unit.v \
     warp_v_core_mul.sv sv_url_inc/picorv32_pcpi_div.sv sv_url_inc/picorv32_pcpi_fast_mul.sv"

build() {   # <program> <output name> [extra cflags] -> $BUILD/<name>.hex
    $CC ${@:3} -T sw/link.ld sw/crt0.s sw/parallel.c sw/programs/$1.c -o $BUILD/$2.elf &&
    riscv64-unknown-elf-objcopy -O verilog $BUILD/$2.elf $BUILD/$2.hex
}

simulate() {  # <name> -> output; same image in both L1Is and in data memory
    local hex=$BUILD/$1.hex
    iverilog -g2012 -o $BUILD/$1.vvp -D C0_FILE=\"$hex\" -D C1_FILE=\"$hex\" -D MEM_FILE=\"$hex\" \
        tests/tb_coherence.v $RTL && vvp -n $BUILD/$1.vvp +EXIT_ONLY +TIMEOUT=2000000 "${@:2}"
}

if [ "$1" == "--speedup" ]; then
    printf "%-12s %12s %12s %8s\n" program "1 core" "2 cores" speedup
    for p in array_sum matmul work_queue; do
        build $p ${p}_w1 -DNUM_WORKERS=1 && build $p ${p}_w2 -DNUM_WORKERS=2 || exit 1
        # array_sum/matmul print their kernel cycles; work_queue is timed end to end
        c1=$(simulate ${p}_w1 | grep -o 'cycles = [0-9]*\|C0 done at cycle [0-9]*' | head -1 | grep -o '[0-9]*$')
        c2=$(simulate ${p}_w2 | grep -o 'cycles = [0-9]*\|C0 done at cycle [0-9]*' | head -1 | grep -o '[0-9]*$')
        printf "%-12s %12s %12s %7.2fx\n" $p $c1 $c2 $(echo "$c1 / $c2" | bc -l)
    done
    exit 0
fi

PROGRAMS=${@:-$(ls sw/programs/*.c | xargs -n1 basename | sed 's/\.c$//')}
for p in $PROGRAMS; do
    build $p $p || { echo "FAIL  $p (build)"; exit 1; }
done

# Simulate in parallel, then report in order
for p in $PROGRAMS; do
    simulate $p +C0_EXPECT=0 +C1_EXPECT=0 > $BUILD/$p.log 2>&1 &
    while [ $(jobs -r | wc -l) -ge $(nproc) ]; do wait -n; done
done
wait

pass=0; fail=0
for p in $PROGRAMS; do
    out=$(cat $BUILD/$p.log)
    if grep -q TEST_PASS <<< "$out" && ! grep -q L2_ERROR <<< "$out"; then
        echo "PASS  $p"; pass=$((pass+1))
    else
        echo "FAIL  $p"; fail=$((fail+1))
    fi
    grep -E '^\[core|INVARIANT_FAIL|L2_ERROR|done at|TEST_FAIL' <<< "$out" | sed 's/^/      /'
done
echo "----------------------------------------"
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
