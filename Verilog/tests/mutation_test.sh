#!/bin/bash
# Mutation testing: injects one plausible bug at a time into a copy of the RTL
# and checks that the regression suite catches it ("killed"). A mutant that
# survives points at a hole in the tests (or at a change that is harmless).
#
# Usage: ./tests/mutation_test.sh

cd "$(dirname "$0")/.."
WORK=tests/build/mutants
mkdir -p $WORK

# name | file | python expression applied to the file text (s)
MUTANTS=$(cat <<'EOF'
no_sm_to_im_on_race|L1_CC.v|s.replace("states[snp_index] <= IM_D;", ";", 1)
no_writeback_after_gets_forward|bus_arbiter.v|s.replace("state <= req_we ? IDLE : WB_LATCH;", "state <= IDLE;")
getm_writes_l2|bus_arbiter.v|s.replace("l2_we <= 0;\n                        state <= ACCESS_L2;", "l2_we <= req_we;\n                        state <= ACCESS_L2;")
request_while_evicting|L1_CC.v|s.replace("is_stable && !evict_active && !snoop_req", "is_stable && !snoop_req")
request_during_snoop|L1_CC.v|s.replace("&& !snoop_req && !link_push_req) begin", ") begin")
m_stays_m_on_gets|L1_CC.v|s.replace("states[snp_index] <= S;\n", ";\n", 1)
s_not_invalidated|L1_CC.v|s.replace("// GetM --> S → I  \n                                states[snp_index] <= I;", ";")
ignore_link_data|L1_CC.v|s.replace("link_push_valid ? link_data_in : bus_rdata", "bus_rdata")
no_store_merge_on_fill|L1_CC.v|s.replace("(eff_cpu_we && req_offset == w && eff_cpu_wmask[b])", "1'b0")
no_byte_mask|L1D_cache.v|s.replace("if (word_write_mask[b])", "if (1'b1)")
arbiter_live_address|bus_arbiter.v|s.replace("l2_addr <= req_addr;\n                        l2_we <= 0;", "l2_addr <= serving_c0 ? c0_bus_addr : c1_bus_addr;\n                        l2_we <= 0;")
no_tag_update_on_fill|L1_CC.v|s.replace("tags[saved_cpu_addr[11:4]] <= saved_cpu_addr[31:12];", ";")
release_during_eviction|L1_CC.v|s.replace("wire stall_release = (bus_ready && !evict_active);", "wire stall_release = bus_ready;")
no_putm|L1_CC.v|s.replace("bus_put        <= 1;   // PutM writeback", "bus_put        <= 0;")
writeback_wrong_core|bus_arbiter.v|s.replace("serving_c0 ? c1_link_data : c0_link_data", "serving_c0 ? c0_link_data : c1_link_data")
snoop_dirty_on_s|L1_CC.v|s.replace("(states[snp_index] == M);", "(states[snp_index] == M || states[snp_index] == S);")
stale_rdata_on_release|L1_CC.v|s.replace("(stall_release && is_fill) ? incoming_word : sram_word_read_data", "sram_word_read_data")
drop_muldiv_on_stall|warp_v_core_mul.sv|s.replace("(!dmem_stall_in || FETCH_Instr_commit_second_issue_a0)", "!dmem_stall_in")
no_putm_cancel|L1_CC.v|s.replace("if (evict_active && snp_index == saved_cpu_addr[11:4]) begin", "if (1'b0) begin")
lock_no_same_cycle_priority|sync_unit.v|s.replace("wire c1_lock_held = locks[c1_lock_id] || (c0_claims && c0_lock_id == c1_lock_id);", "wire c1_lock_held = locks[c1_lock_id];")
counter_lost_same_cycle_bump|sync_unit.v|s.replace("counters[n] <= c1_rdata + 1;", "counters[n] <= counters[n] + 1;")
barrier_misses_same_cycle_arrival|sync_unit.v|s.replace("if ((arrived | arrive_now) == 2'b11) begin", "if (arrived == 2'b11) begin")
io_goes_to_cache|module_top.v|s.replace("wire        c0_io = c0_req && c0_addr[31];", "wire        c0_io = 1'b0;")
speculative_mem_requests|warp_v_core_mul.sv|s.replace("assign dmem_req_out = FETCH_Instr_valid_st_a0 || FETCH_Instr_valid_ld_a0;", "assign dmem_req_out = FETCH_Instr_valid_st_a0 || FETCH_Instr_spec_ld_a0;")
EOF
)

# Mutants that cannot change behaviour, so surviving is correct:
#   drop_muldiv_on_stall  only committed loads request memory, so the core is never stalled
#                         when a mul/div result is written back (the fix stays as a guard)
#   no_putm_cancel        the cancelled PutM would only rewrite data that was already
#                         forwarded or superseded; cancelling it saves a bus transaction
EQUIVALENT=" drop_muldiv_on_stall no_putm_cancel "

killed=0; survived=0; equivalent=0
while IFS='|' read -r name file expr; do
    dir=$WORK/$name
    mkdir -p $dir/tests
    cp *.v *.sv link.ld $dir/ && cp -r sv_url_inc Assembly_files C_programs sw $dir/ &&
    cp -r tests/asm tests/*.sh tests/*.py tests/*.v $dir/tests/
    python3 - "$dir/$file" "$expr" <<'PY'
import sys
path, expr = sys.argv[1], sys.argv[2]
s = open(path).read()
t = eval(expr)
if t == s:
    sys.exit("mutation did not apply: " + expr)
open(path, "w").write(t)
PY
    [ $? -eq 0 ] || { echo "ERROR  $name: mutation did not apply"; continue; }
    # Mutants often hang a test, so use a timeout just above the slowest passing test
    if VVP_ARGS=+TIMEOUT=50000 RAND_SEEDS="$(seq 1 16)" $dir/tests/run_all.sh > $dir/result.txt 2>&1; then
        if [[ $EQUIVALENT == *" $name "* ]]; then
            echo "survived  $name  (equivalent mutant, expected)"; equivalent=$((equivalent+1))
        else
            echo "SURVIVED  $name"; survived=$((survived+1))
        fi
    else
        echo "killed    $name  ($(tail -1 $dir/result.txt | awk '{print $3}') tests failed)"; killed=$((killed+1))
    fi
done <<< "$MUTANTS"
echo "----------------------------------------"
echo "$killed killed, $survived survived, $equivalent equivalent"
[ $survived -eq 0 ]
