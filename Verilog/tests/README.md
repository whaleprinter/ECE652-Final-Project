# Verification

```
./tests/run_all.sh                 # everything (about 15 s on 4 CPUs)
./tests/run_all.sh upgrade_race    # one test
./tests/mutation_test.sh           # check that the suite catches injected bugs
../sw/run.sh                       # parallel C programs (see sw/README.md)
```

Needs `iverilog`, `python3` and `riscv64-unknown-elf-gcc`.

## Testbench (`tb_coherence.v`)

Every system test runs on the full dual-core design. The testbench checks:

* **Results.** Each core reports a result, either in `x31` after writing 1 to
  `x30` or through the sync unit's EXIT register. It must match the expected
  value.
* **Single writer / multiple readers.** On every idle bus cycle, no block may
  be M in one L1 while valid in the other.
* **Data value.** On every idle bus cycle, every block held in S must match L2.
* **Address range.** Any access beyond the 16 KB memory is an error, because
  it would alias.

It also records **coverage**: every L1 state transition, every
(request, state of that block in the other L1) snoop pair, and key protocol
events. `run_all.sh` merges coverage over all tests and flags any point that
no test reached.

## Tests

| Group | What it does |
|---|---|
| `arbiter_unit`, `sync_unit` | unit tests, including same-cycle requests from both cores |
| directed (`asm/`) | your microbenchmarks with pass/fail checks, plus a reproducer for every bug fixed |
| `race_*` (`gen_races.py`) | ten targeted races on one block (upgrade vs GetS, eviction vs GetM, ...), each swept over all 64 relative timings, with exact checks of every word afterwards |
| `litmus_*` (`gen_litmus.py`) | SB, LB, 2+2W and MP litmus tests, same block and different blocks: no outcome forbidden by sequential consistency may appear. `x29` counts outcomes that show the accesses really overlapped |
| `random_*` (`gen_random.py`) | 32 seeds of random false sharing with conflict evictions. **Every load is checked**: a core reads back exactly its own last write, and never sees another core's word go back in time |
| `c_*` | the original C benchmarks |

## Mutation testing

`mutation_test.sh` injects one realistic bug at a time into a copy of the RTL
(for example: skip the SM_D->IM_D transition, forget the writeback after
forwarding to a GetS, drop the byte mask, let a store miss write L2, break
same-cycle lock priority) and runs the suite. Every mutant should be
"killed", meaning at least one test fails.
