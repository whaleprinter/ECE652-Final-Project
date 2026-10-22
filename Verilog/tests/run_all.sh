#!/bin/bash
# Builds every test program, runs each one on the dual-core system with the
# invariant- and coverage-checking testbench (in parallel), and reports
# PASS/FAIL plus a protocol coverage summary.
#
# Usage (from anywhere):  ./tests/run_all.sh [test_name ...]
#   VVP_ARGS=+NO_INVARIANTS   check only the program results
#   RAND_SEEDS="1 2 3"        choose the random-test seeds (default 1..32)
#   JOBS=n                    parallel simulations (default: number of CPUs)

cd "$(dirname "$0")/.."

BUILD=tests/build
mkdir -p $BUILD
export BUILD VVP_ARGS

CC="riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -ffreestanding"
export RTL="module_top.v L1_CC.v bus_arbiter.v L1D_cache.v L2_cache.v L1I_cache.v sync_unit.v \
     warp_v_core_mul.sv sv_url_inc/picorv32_pcpi_div.sv sv_url_inc/picorv32_pcpi_fast_mul.sv"
RAND_SEEDS=${RAND_SEEDS:-$(seq 1 32)}
JOBS=${JOBS:-$(nproc)}

check_size() { # programs must fit the 4 KB L1I
    local text=$(riscv64-unknown-elf-size $BUILD/$1.elf | awk 'NR==2 {print $1}')
    [ $text -le 4096 ] || { echo "ERROR: $1 is $text bytes, larger than the 4 KB L1I"; return 1; }
}

build_asm() {  # <name> [dir] -> $BUILD/<name>.hex
    $CC -Ttext=0 -Wl,--entry=0 -o $BUILD/$1.elf ${2:-tests/asm}/$1.s &&
    riscv64-unknown-elf-objcopy -O verilog $BUILD/$1.elf $BUILD/$1.hex &&
    check_size $1
}

build_c() {    # <boot> <c file> <name>
    $CC -O1 -T link.ld Assembly_files/$1.s C_programs/$2.c -o $BUILD/$3.elf &&
    riscv64-unknown-elf-objcopy -O verilog $BUILD/$3.elf $BUILD/$3.hex &&
    check_size $3
}

# ---------------------------------------------------------------- build
for f in tests/asm/*.s; do build_asm $(basename $f .s) || exit 1; done
for seed in $RAND_SEEDS; do
    python3 tests/gen_random.py $seed 120 $BUILD || exit 1
    build_asm rand${seed}_c0 $BUILD && build_asm rand${seed}_c1 $BUILD || exit 1
done
LITMUS=$(python3 tests/gen_litmus.py $BUILD) || exit 1
LITMUS+=" $(python3 tests/gen_races.py $BUILD)" || exit 1
for t in $LITMUS; do build_asm ${t}_c0 $BUILD && build_asm ${t}_c1 $BUILD || exit 1; done
# Parallel C programs on the sync-unit runtime (the fast ones; sw/run.sh runs them all)
SW_PROGRAMS="hello lock_counter peterson queue array_sum"
for p in $SW_PROGRAMS; do
    $CC -Os -Isw -Wl,--no-warn-rwx-segments -T sw/link.ld sw/crt0.s sw/parallel.c sw/programs/$p.c -o $BUILD/sw_$p.elf &&
    riscv64-unknown-elf-objcopy -O verilog $BUILD/sw_$p.elf $BUILD/sw_$p.hex || exit 1
done
build_c boot_c0 test_sum  test_sum  || exit 1
build_c boot_c0 test_fac  test_fac  || exit 1
build_c boot_c0 matmul_c0 matmul_c0 || exit 1
build_c boot_c1 matmul_c1 matmul_c1 || exit 1

# ---------------------------------------------------------------- test list
#   name               core 0 program        core 1 program        C0 x31   C1 x31
TESTS="
sync_array             sync_array_c0         sync_array_c1         0        100
prodcons               prodcons_c0           prodcons_c1           0        1500
thrash                 thrash_c0             thrash_c1             3276850  0
evict                  evict_c0              evict_c1              0        260
store_miss_fill        store_miss_fill_c0    idle                  2849     0
dirty_share_wb         dirty_share_wb_c0     dirty_share_wb_c1     85       85
upgrade_race           upgrade_race_c0       upgrade_race_c1       3276850  0
evict_then_snoop       evict_then_snoop_c0   evict_then_snoop_c1   77       0
muldiv_miss            muldiv_miss_c0        idle                  333      0
mul_dep                mul_dep_c0            idle                  141      0
subword                subword_c0            idle                  0        0
io_after_mul           io_after_mul_c0       idle                  0        0
c_sum                  test_sum              idle                  150      0
c_factorial            test_fac              idle                  3628800  0
c_matmul               matmul_c0             matmul_c1             72       200
"
for t in tests/asm/*_c0.s; do      # tests that declare "# EXPECT: <c0> <c1>" themselves
    exp=$(grep -o '^# EXPECT: .*' $t | cut -d' ' -f3-)
    [ -n "$exp" ] && TESTS+="$(basename $t _c0.s) $(basename $t .s) $(basename $t _c0.s)_c1 $exp"$'\n'
done
for p in $SW_PROGRAMS; do       # same image on both cores and in data memory
    TESTS+="sw_$p sw_$p sw_$p 0 0 spmd"$'\n'
done
for t in $LITMUS; do
    TESTS+="$t ${t}_c0 ${t}_c1 0 0"$'\n'
done
for seed in $RAND_SEEDS; do
    TESTS+="random_$seed rand${seed}_c0 rand${seed}_c1 0 0"$'\n'
done

if [ $# -gt 0 ]; then
    TESTS=$(echo "$TESTS" | awk -v sel=" $* " 'NF && index(sel, " " $1 " ")')
fi

# ---------------------------------------------------------------- run
run_one() {    # <name> <c0 hex> <c1 hex> <c0 expect> <c1 expect> [spmd]
    local name=$1 out defs="" args=""
    if [ "$6" == "spmd" ]; then
        defs="-D MEM_FILE=\"$BUILD/$2.hex\""; args="+EXIT_ONLY"
    fi
    if ! iverilog -g2012 -o $BUILD/$name.vvp -D C0_FILE=\"$BUILD/$2.hex\" -D C1_FILE=\"$BUILD/$3.hex\" $defs \
            tests/tb_coherence.v $RTL > $BUILD/$name.log 2>&1; then
        echo "FAIL  $name (compile)"; return
    fi
    out=$(vvp -n $BUILD/$name.vvp +C0_EXPECT=$4 +C1_EXPECT=$5 $args $VVP_ARGS)
    echo "$out" > $BUILD/$name.log
    if grep -q "TEST_PASS" <<< "$out" && ! grep -q "L2_ERROR" <<< "$out"; then
        echo "PASS  $name  ($(grep -o 'done at cycle [0-9]*' <<< "$out" | grep -o '[0-9]*$' | sort -n | tail -1) cycles)"
    else
        echo "FAIL  $name"
        grep -E "INVARIANT_FAIL|L2_ERROR|done at|TEST_FAIL" <<< "$out" | head -6 | sed 's/^/      /'
    fi
}
export -f run_one

RESULTS=$(
    # Unit tests: <name> <testbench> <rtl...>
    while read -r name tb rtl; do
        [ -z "$name" ] && continue
        if [ $# -eq 0 ] || [[ " $* " =~ " $name " ]]; then
            iverilog -g2012 -o $BUILD/$name.vvp tests/$tb $rtl &&
            out=$(vvp -n $BUILD/$name.vvp)
            if grep -q TEST_PASS <<< "$out"; then echo "PASS  $name"
            else echo "FAIL  $name"; grep FAIL <<< "$out" | sed 's/^/      /'; fi
        fi
    done <<< "
arbiter_unit    tb_arbiter_unit.v  bus_arbiter.v L2_cache.v
sync_unit       tb_sync_unit.v     sync_unit.v
"
    echo "$TESTS" | awk 'NF' | xargs -r -P $JOBS -L 1 bash -c 'run_one "$@"' _
)

# Print results in a stable order, each failure followed by its detail lines
echo "$RESULTS" | awk '/^(PASS|FAIL)/ {key=$2} {print key "\t" NR "\t" $0}' | sort -t$'\t' -k1,1V -k2,2n | cut -f3-

PASS=$(grep -c '^PASS' <<< "$RESULTS")
FAIL=$(grep -c '^FAIL' <<< "$RESULTS")

# ---------------------------------------------------------------- coverage
if [ $# -eq 0 ]; then
    python3 tests/coverage.py $(echo "$TESTS" | awk -v b=$BUILD 'NF {print b "/" $1 ".log"}')
fi

echo "----------------------------------------"
echo "$PASS passed, $FAIL failed $(grep '^FAIL' <<< "$RESULTS" | awk '{print $2}' | tr '\n' ' ')"
[ $FAIL -eq 0 ]
