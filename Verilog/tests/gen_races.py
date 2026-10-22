#!/usr/bin/env python3
"""Generates race-sweep tests: targeted two-core races on one block.

Each scenario puts a block in a chosen state in both L1s, then both cores hit
it at once, with core 0 delayed iter % 8 cycles and core 1 (iter / 8) % 8
cycles, so all 64 relative timings are tried. Every iteration uses a fresh
block (a different cache index), and "conflict" blocks share that index to
force evictions. After each race both cores check every word of the block.

Words are written by one core each, so the checks are exact:
  * a word that was written must hold its value afterwards (no lost write);
  * a racing load must return either the old or the new value of its word.

x31 counts failed checks on each core.

Usage: gen_races.py <out dir>   (writes race_<name>_c0.s / _c1.s)
"""
import sys

out = sys.argv[1]
ITER = 64
BASE = 0x1000           # block for iteration i: BASE + 16*i  (index i)
CONFLICT = 0x2000       # same index, different tag: BASE + CONFLICT + 16*i
CNT = [0x900, 0x940]    # barrier counters

# Ops: (kind, word) on the race block, or ("evict",) to touch the conflict block.
# Setup ops run before the race (separated by a barrier).
SCENARIOS = {
    # name:              (setup c0,             setup c1,             race c0,         race c1)
    "upgrade_vs_gets":   ([("ld", 2)],          [],                   ("st", 0),       ("ld", 0)),
    "upgrade_vs_upgrade":([("ld", 2)],          [("ld", 2)],          ("st", 0),       ("st", 1)),
    "upgrade_vs_getm":   ([("ld", 2)],          [],                   ("st", 0),       ("st", 1)),
    "gets_vs_gets":      ([],                   [],                   ("ld", 0),       ("ld", 1)),
    "getm_vs_getm":      ([],                   [],                   ("st", 0),       ("st", 1)),
    "gets_vs_getm":      ([],                   [],                   ("ld", 1),       ("st", 1)),
    "evict_vs_gets":     ([("st", 2)],          [],                   ("evict",),      ("ld", 2)),
    "evict_vs_getm":     ([("st", 2)],          [],                   ("evict",),      ("st", 1)),
    "evict_vs_evict":    ([("st", 2)],          [("evict_st",)],      ("evict",),      ("ld", 2)),
    "load_vs_owner_store": ([],                 [("st", 3)],          ("ld", 3),       ("st", 3)),
}


def barrier():
    return ["    addi s5, s5, 1", "    sw s5, 0(s6)",
            "1:  lw t1, 0(s7)", "    blt t1, s5, 1b"]


def delay(reg):
    return ["    la t0, 3f", f"    slli t1, {reg}, 2", "    sub t0, t0, t1", "    jr t0"] + \
           ["    nop"] * 15 + ["3:"]


label = [0]


def fail_unless(cond_lines):
    """cond_lines branch to the returned label when the check passes."""
    label[0] += 1
    ok = f"ok{label[0]}"
    return [line.replace("@OK", ok) for line in cond_lines] + ["    addi x31, x31, 1", f"{ok}:"]


def value(core, word):
    # Distinct per core, word and iteration: (core+1)<<12 | word<<8 | iteration
    return f"(({core + 1} << 12) | ({word} << 8))"


def emit_op(core, op):
    if op[0] == "ld":
        return [f"    lw t2, {4 * op[1]}(s0)"]
    if op[0] == "st":
        return [f"    li t2, {value(core, op[1])}", "    or t2, t2, s9", f"    sw t2, {4 * op[1]}(s0)"]
    if op[0] == "evict":
        return ["    lw t2, 0(s1)"]
    if op[0] == "evict_st":
        return ["    sw s9, 0(s1)"]
    raise ValueError(op)


def scenario(name, setup0, setup1, race0, race1):
    setups = (setup0, setup1)
    races = (race0, race1)
    # Final value of each word: written by setup or race stores (one writer per word,
    # except a word stored in setup and again in the race by the same core)
    final = {}
    for core in (0, 1):
        for op in setups[core] + [races[core]]:
            if op[0] == "st":
                final[op[1]] = (core, op[1])
    progs = []
    for core in (0, 1):
        p = [f"# EXPECT: 0 0", f"# Race {name}, core {core}",
             "    li s5, 0", f"    li s6, {CNT[core]:#x}", f"    li s7, {CNT[1 - core]:#x}",
             "    li s9, 0", "    li x31, 0",
             "iter:",
             "    slli t0, s9, 4", f"    li s0, {BASE:#x}", "    add s0, s0, t0",
             f"    li t0, {CONFLICT:#x}", "    add s1, s0, t0"]
        for op in setups[core]:
            p += emit_op(core, op)
        p += barrier()
        p += ["    andi a0, s9, 7"] if core == 0 else ["    srli a0, s9, 3", "    andi a0, a0, 7"]
        p += delay("a0")
        p += emit_op(core, races[core])
        # A racing load must see the old or the new value of its word
        op = races[core]
        if op[0] == "ld" and op[1] in final:
            w = op[1]
            writer, _ = final[w]
            new = f"    li t3, {value(writer, w)}"
            old_written_in_setup = any(o == ("st", w) for o in setups[writer])
            checks = [new, "    or t3, t3, s9", "    beq t2, t3, @OK"]
            if old_written_in_setup or writer == core:
                checks += []      # value was already final before the race
            else:
                checks += ["    beqz t2, @OK"]
            p += fail_unless(checks)
        p += barrier()
        # Both cores check every word of the block
        for w in range(4):
            p += [f"    lw t2, {4 * w}(s0)"]
            if w in final:
                writer, _ = final[w]
                p += fail_unless([f"    li t3, {value(writer, w)}", "    or t3, t3, s9", "    beq t2, t3, @OK"])
            else:
                p += fail_unless(["    beqz t2, @OK"])
        p += barrier()
        p += ["    addi s9, s9, 1", f"    li t0, {ITER}", "    blt s9, t0, iter",
              "    li x30, 1", "halt: j halt"]
        progs.append(p)
    return progs


names = []
for name, spec in SCENARIOS.items():
    c0, c1 = scenario(name, *spec)
    names.append(f"race_{name}")
    for core, prog in ((0, c0), (1, c1)):
        with open(f"{out}/race_{name}_c{core}.s", "w") as f:
            f.write("\n".join(prog) + "\n")
print(" ".join(names))
