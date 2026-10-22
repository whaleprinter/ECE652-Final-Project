#!/bin/bash
# Builds every test program, runs it on the dual-core system with the
# invariant-checking testbench, and reports PASS/FAIL.
#
# Usage (from anywhere):  ./tests/run_all.sh [test_name ...]
# Set VVP_ARGS=+NO_INVARIANTS to check only the program results.

cd "$(dirname "$0")/.."

BUILD=tests/build
mkdir -p $BUILD

CC="riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -ffreestanding"
RTL="module_top.v L1_CC.v bus_arbiter.v L1D_cache.v L2_cache.v L1I_cache.v warp_v_core_mul.sv \
     sv_url_inc/picorv32_pcpi_div.sv sv_url_inc/picorv32_pcpi_fast_mul.sv"

build_asm() {  # <name> [dir] -> $BUILD/<name>.hex
    $CC -Ttext=0 -Wl,--entry=0 -o $BUILD/$1.elf ${2:-tests/asm}/$1.s &&
    riscv64-unknown-elf-objcopy -O verilog $BUILD/$1.elf $BUILD/$1.hex &&
    check_size $1
}

check_size() { # programs must fit the 4 KB L1I
    local text=$(riscv64-unknown-elf-size $BUILD/$1.elf | awk 'NR==2 {print $1}')
    [ $text -le 4096 ] || { echo "ERROR: $1 is $text bytes, larger than the 4 KB L1I"; return 1; }
}

build_c() {    # <boot> <c file> <name>
    $CC -O1 -T link.ld Assembly_files/$1.s C_programs/$2.c -o $BUILD/$3.elf &&
    riscv64-unknown-elf-objcopy -O verilog $BUILD/$3.elf $BUILD/$3.hex
}

PASS=0
FAIL=0
FAILED=()

run() {        # <name> <c0 hex> <c1 hex> <c0 expect> <c1 expect>
    local name=$1
    if [ ${#SELECT[@]} -gt 0 ] && [[ ! " ${SELECT[*]} " =~ " $name " ]]; then return; fi
    iverilog -g2012 -o $BUILD/$name.vvp \
        -D C0_FILE=\"$BUILD/$2.hex\" -D C1_FILE=\"$BUILD/$3.hex\" \
        tests/tb_coherence.v $RTL || { echo "FAIL  $name (compile)"; FAIL=$((FAIL+1)); FAILED+=($name); return; }
    local out
    out=$(vvp -n $BUILD/$name.vvp +C0_EXPECT=$4 +C1_EXPECT=$5 $VVP_ARGS)
    if grep -q "TEST_PASS" <<< "$out"; then
        echo "PASS  $name  ($(grep -o 'done at cycle [0-9]*' <<< "$out" | tail -1 | grep -o '[0-9]*$') cycles)"
        PASS=$((PASS+1))
    else
        echo "FAIL  $name"
        grep -E "INVARIANT_FAIL|done at|TEST_FAIL" <<< "$out" | head -6 | sed 's/^/      /'
        FAIL=$((FAIL+1)); FAILED+=($name)
    fi
}

SELECT=("$@")

# Unit test: arbiter + L2
if [ ${#SELECT[@]} -eq 0 ] || [[ " ${SELECT[*]} " =~ " arbiter_unit " ]]; then
    iverilog -g2012 -o $BUILD/arbiter_unit.vvp tests/tb_arbiter_unit.v bus_arbiter.v L2_cache.v &&
    out=$(vvp -n $BUILD/arbiter_unit.vvp)
    if grep -q TEST_PASS <<< "$out"; then echo "PASS  arbiter_unit"; PASS=$((PASS+1))
    else echo "FAIL  arbiter_unit"; grep FAIL <<< "$out" | sed 's/^/      /'; FAIL=$((FAIL+1)); FAILED+=(arbiter_unit); fi
fi

for f in tests/asm/*.s; do build_asm $(basename $f .s) || exit 1; done
RAND_SEEDS="1 2 3 4 5 6 7 8"
for seed in $RAND_SEEDS; do
    python3 tests/gen_random.py $seed 180 $BUILD || exit 1
    build_asm rand${seed}_c0 $BUILD && build_asm rand${seed}_c1 $BUILD || exit 1
done
build_c boot_c0 test_sum  test_sum  || exit 1
build_c boot_c0 test_fac  test_fac  || exit 1
build_c boot_c0 matmul_c0 matmul_c0 || exit 1
build_c boot_c1 matmul_c1 matmul_c1 || exit 1

#   name               core 0 program        core 1 program        C0 x31   C1 x31
run sync_array         sync_array_c0         sync_array_c1         0        100
run prodcons           prodcons_c0           prodcons_c1           0        1500
run thrash             thrash_c0             thrash_c1             3276850  0
run evict              evict_c0              evict_c1              0        260
run store_miss_fill    store_miss_fill_c0    idle                  2849     0
run dirty_share_wb     dirty_share_wb_c0     dirty_share_wb_c1     85       85
run upgrade_race       upgrade_race_c0       upgrade_race_c1       3276850  0
run evict_then_snoop   evict_then_snoop_c0   evict_then_snoop_c1   77       0
run muldiv_miss        muldiv_miss_c0        idle                  333      0
run mul_dep            mul_dep_c0            idle                  141      0
run subword            subword_c0            idle                  0        0
run c_sum              test_sum              idle                  150      0
run c_factorial        test_fac              idle                  3628800  0
run c_matmul           matmul_c0             matmul_c1             72       200
for seed in $RAND_SEEDS; do
run random_$seed       rand${seed}_c0        rand${seed}_c1        0        0
done

echo "----------------------------------------"
echo "$PASS passed, $FAIL failed ${FAILED[*]}"
[ $FAIL -eq 0 ]
