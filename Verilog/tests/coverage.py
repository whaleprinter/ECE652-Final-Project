#!/usr/bin/env python3
"""Merges the "COV ..." lines printed by tb_coherence.v across test logs and
reports which protocol transitions, snoop cases and events were exercised.

Usage: coverage.py <log> [<log> ...]
"""
import collections
import sys

# Every transition the MSI controller can make (see L1_CC.v)
TRANSITIONS = [
    ("I", "IS_D", "load miss"),
    ("I", "IM_D", "store miss"),
    ("S", "IS_D", "load miss replaces a clean block"),
    ("S", "IM_D", "store miss replaces a clean block"),
    ("S", "SM_D", "store hit on S: upgrade"),
    ("S", "I", "invalidated by other core's GetM"),
    ("M", "S", "other core's GetS: forward + writeback"),
    ("M", "I", "other core's GetM: forward"),
    ("M", "IS_D", "load miss after dirty eviction (or eviction cancelled by a snoop)"),
    ("M", "IM_D", "store miss after dirty eviction (or eviction cancelled by a snoop)"),
    ("IS_D", "S", "load fill"),
    ("IM_D", "M", "store fill"),
    ("SM_D", "M", "upgrade granted"),
    ("SM_D", "IM_D", "upgrade lost the race to other core's GetM"),
]

# Snooped block's state in the snooped core when a request arrives
SNOOPS = [
    ("GetS", "I"), ("GetM", "I"),
    ("GetS", "S"), ("GetM", "S"),
    ("GetS", "M"), ("GetM", "M"),
    ("GetS", "IS_D"), ("GetM", "IS_D"),
    ("GetS", "IM_D"), ("GetM", "IM_D"),
    ("GetS", "SM_D"), ("GetM", "SM_D"),
]

EVENTS = [
    "putm", "putm_cancelled_by_snoop", "forward_on_GetS", "forward_on_GetM",
    "writeback_after_GetS_forward", "fill_from_link", "fill_from_L2",
    "upgrade_without_data", "both_cores_request_same_cycle",
]

counts = collections.Counter()
tests_hitting = collections.defaultdict(set)
for path in sys.argv[1:]:
    try:
        lines = open(path).read().splitlines()
    except OSError:
        continue
    name = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    for line in lines:
        parts = line.split()
        if len(parts) == 4 and parts[0] == "COV":
            key = (parts[1], parts[2])
            n = int(parts[3])
            counts[key] += n
            if n:
                tests_hitting[key].add(name)

missing = 0


def row(key, desc):
    global missing
    n = counts[key]
    if n == 0:
        missing += 1
    mark = "  " if n else "!!"
    print(f"  {mark} {key[1]:<34} {n:>8}  {len(tests_hitting[key]):>3} tests  {desc}")


print("Protocol coverage (count, number of tests that hit it):")
print(" transitions")
for a, b, desc in TRANSITIONS:
    row(("transition", f"{a}->{b}"), desc)
print(" snoops (request @ state of that block in the other L1)")
for t, st in SNOOPS:
    row(("snoop", f"{t}@{st}"), "")
print(" events")
for e in EVENTS:
    row(("event", e), "")
unexpected = [k for k in counts if k[0] == "transition" and
              k[1] not in {f"{a}->{b}" for a, b, _ in TRANSITIONS}]
for k in unexpected:
    print(f"  ?? unexpected transition {k[1]} seen {counts[k]} times")
print(f" {missing} coverage points not hit" if missing else " all coverage points hit")
