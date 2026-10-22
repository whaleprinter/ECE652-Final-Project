#!/usr/bin/env python3
"""Generates memory-consistency litmus tests for the two cores.

Each test runs a classic two-thread litmus shape many times. Iterations are
separated by a shared-memory barrier, and each core waits a different number
of cycles before its part (the delays sweep every offset from -7 to +7), so
the racing accesses line up differently every time. Core 0 counts the
outcomes that sequential consistency forbids; x31 must end at 0. It also
counts, in x29, an allowed outcome that only happens when the two cores'
accesses really overlap, to show the races are being exercised.

  sb    store buffering   x=1; r0=y   ||  y=1; r1=x     forbidden: r0=0, r1=0
  lb    load buffering    r0=x; y=1   ||  r1=y; x=1     forbidden: r0=1, r1=1
  2+2w  write order       x=1; y=2    ||  y=1; x=2      forbidden: x=1, y=1 at the end
  mp    message passing   data=i; flag=i  ||  f=flag; d=data   forbidden: d < f

Each shape runs with x and y in different blocks and in the same block
(false sharing), which exercise different coherence paths.

Usage: gen_litmus.py <out dir>   (writes litmus_<name>_c0.s / _c1.s)
"""
import sys

out = sys.argv[1]
ITER = 64
X = 0x500
Y = {"diff": 0x540, "same": 0x504}
CNT = [0x900, 0x940]      # per-core barrier counters
RES1 = 0x980              # core 1's observed value

SHAPES = {
    "sb":   (["li t0, 1", "sw t0, 0(s0)", "lw s3, 0(s1)"],
             ["li t0, 1", "sw t0, 0(s1)", "lw s3, 0(s0)"]),
    "lb":   (["lw s3, 0(s0)", "li t0, 1", "sw t0, 0(s1)"],
             ["lw s3, 0(s1)", "li t0, 1", "sw t0, 0(s0)"]),
    "2+2w": (["li t0, 1", "sw t0, 0(s0)", "li t0, 2", "sw t0, 0(s1)"],
             ["li t0, 1", "sw t0, 0(s1)", "li t0, 2", "sw t0, 0(s0)"]),
}


def barrier():
    return ["    addi s5, s5, 1", "    sw s5, 0(s6)",
            "1:  lw t1, 0(s7)", "    blt t1, s5, 1b"]


def delay(reg):
    # Jump into a sled of nops: waits exactly <reg> cycles (0..15), one cycle per step
    return ["    la t0, 3f", f"    slli t1, {reg}, 2", "    sub t0, t0, t1", "    jr t0"] + \
           ["    nop"] * 15 + ["3:"]


def litmus(shape, place):
    x, y = X, Y[place]
    progs = []
    for core in (0, 1):
        body = SHAPES[shape][core]
        p = [f"# EXPECT: 0 0", f"# Litmus {shape} ({place} block), core {core}",
             f"    li s0, {x:#x}", f"    li s1, {y:#x}",
             "    li s5, 0", f"    li s6, {CNT[core]:#x}", f"    li s7, {CNT[1 - core]:#x}",
             f"    li s8, {RES1:#x}", "    li s9, 0", "    li x31, 0", "    li x29, 0",
             "iter:"]
        if core == 0:
            p += ["    sw x0, 0(s0)", "    sw x0, 0(s1)"]
        p += barrier()
        # delays: core 0 waits iter % 8, core 1 waits (iter / 8) % 8
        p += ["    andi a0, s9, 7"] if core == 0 else ["    srli a0, s9, 3", "    andi a0, a0, 7"]
        p += delay("a0")
        p += ["    " + i for i in body]
        p += barrier()
        if core == 1:
            p += ["    sw s3, 0(s8)"]
        p += barrier()
        if core == 0:
            p += ["    lw s4, 0(s8)"]
            if shape == "sb":   # overlap: both stores before both loads (1, 1)
                p += ["    or t0, s3, s4", "    bnez t0, 4f", "    addi x31, x31, 1", "4:",
                      "    and t0, s3, s4", "    beqz t0, 5f", "    addi x29, x29, 1", "5:"]
            elif shape == "lb": # overlap: both loads before both stores (0, 0)
                p += ["    and t0, s3, s4", "    beqz t0, 4f", "    addi x31, x31, 1", "4:",
                      "    or t0, s3, s4", "    bnez t0, 5f", "    addi x29, x29, 1", "5:"]
            else:               # overlap: interleaved writes leave (2, 2)
                p += ["    lw t0, 0(s0)", "    lw t1, 0(s1)", "    li t2, 1",
                      "    bne t0, t2, 4f", "    bne t1, t2, 4f", "    addi x31, x31, 1", "4:",
                      "    li t2, 2", "    bne t0, t2, 5f", "    bne t1, t2, 5f", "    addi x29, x29, 1", "5:"]
        p += ["    addi s9, s9, 1", f"    li t0, {ITER}", "    blt s9, t0, iter"]
        if core == 1:
            p += ["    li x31, 0"]
        p += ["    li x30, 1", "halt: j halt"]
        progs.append(p)
    return progs


def message_passing(place):
    data, flag = X, Y[place]
    n = 100
    c0 = ["# EXPECT: 0 0", f"# Litmus mp ({place} block), core 0",
          f"    li s0, {data:#x}", f"    li s1, {flag:#x}", "    li t0, 1", f"    li t1, {n}",
          "1:  sw t0, 0(s0)", "    sw t0, 0(s1)", "    addi t0, t0, 1", "    ble t0, t1, 1b",
          "    li x31, 0", "    li x30, 1", "halt: j halt"]
    c1 = [f"# Litmus mp ({place} block), core 1",
          f"    li s0, {data:#x}", f"    li s1, {flag:#x}", "    li x31, 0", f"    li t1, {n}",
          "    li x29, 0",
          "1:  lw t2, 0(s1)", "    lw t3, 0(s0)", "    bgeu t3, t2, 2f", "    addi x31, x31, 1",
          "2:  bleu t3, t2, 3f", "    addi x29, x29, 1",
          "3:  blt t2, t1, 1b", "    li x30, 1", "halt: j halt"]
    return c0, c1


tests = {}
for shape in SHAPES:
    for place in Y:
        tests[f"litmus_{shape.replace('+', 'p')}_{place}"] = litmus(shape, place)
for place in Y:
    tests[f"litmus_mp_{place}"] = message_passing(place)

for name, (c0, c1) in tests.items():
    for core, prog in ((0, c0), (1, c1)):
        with open(f"{out}/{name}_c{core}.s", "w") as f:
            f.write("\n".join(prog) + "\n")
print(" ".join(tests))
