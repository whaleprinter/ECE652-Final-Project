# Parallel programming on the dual-core system

Both cores run the **same program** (SPMD). `main()` runs on each core, and
`core_id()` tells them apart. Memory is shared and kept coherent by the MSI
protocol, and because the cores are in-order with no store buffer, it is
**sequentially consistent**. Synchronization comes from a small memory-mapped
**sync unit**, because the WARP-V cores have no atomic instructions.

```c
#include "parallel.h"

int data[1024];
SHARED int partial[2];

int main(void) {
    int begin, end;
    my_range(1024, &begin, &end);       // this core's half
    int sum = 0;
    for (int i = begin; i < end; i++)
        sum += data[i];
    partial[core_id()] = sum;
    barrier();                          // wait for the other core
    return core_id() == 0 ? partial[0] + partial[1] : 0;
}
```

## Running programs

```
./sw/run.sh                  # build and run every program in sw/programs, check exit codes
./sw/run.sh hello matmul     # just these
./sw/run.sh --speedup        # time the parallel kernels on 1 and 2 cores
```

A program passes when both cores return 0 from `main`. The run uses the
invariant-checking testbench, so a coherence violation also fails it. Console
output appears as `[core N] ...` lines.

To add a program, put `myprog.c` in `sw/programs/`. It must fit in the 4 KB
instruction cache (code plus initialized data). The linker stops with an
error if it doesn't.

## Hardware support

### Memory map

| Address | Contents |
|---|---|
| `0x0000 - 0x0FFF` | code, read-only and initialized data (loaded into both L1Is **and** data memory) |
| `0x1000 - 0x2FFF` | zero-initialized globals (`.bss`), shared |
| `0x3000 - 0x37FF` | core 1 stack |
| `0x3800 - 0x3FFF` | core 0 stack |
| `0x8000_0000 +`   | sync unit (uncached I/O) |

Data memory is 16 KB with no tags. Addresses at or above `0x4000` would alias,
and the simulation reports `L2_ERROR` if one is used.

### Sync unit (`sync_unit.v`)

Loads and stores to `0x8000_0000 + offset` bypass the caches and complete in
one cycle. When both cores access it in the same cycle, core 0's access takes
effect first, so every operation is atomic.

| Offset | Register | Read | Write |
|---|---|---|---|
| `0x00` | CORE_ID | 0 or 1 | - |
| `0x04` | NUM_CORES | 2 | - |
| `0x08` | CYCLES | cycle counter | - |
| `0x10` | PUTCHAR | - | print a character |
| `0x14` | EXIT | - | finish this core with an exit code |
| `0x20` | BARRIER | generation | arrive (the generation advances once both cores have arrived) |
| `0x40 + 4i` | LOCK[i], i < 8 | 0 = acquired, 1 = held | release |
| `0x60 + 4i` | COUNTER[i], i < 4 | value, then +1 (fetch-and-add) | set |

The design follows the hardware spinlocks and FIFOs of microcontrollers such
as the RP2040 (its SIO block). The alternative, adding the RISC-V A
extension (LR/SC, AMOs) to the core and the cache controller, would need
changes inside the generated WARP-V core and a reservation mechanism in
`L1_CC`.

## Runtime API (`parallel.h`)

| Function | Purpose |
|---|---|
| `core_id()`, `num_cores()` | which core this is; how many there are |
| `my_range(n, &begin, &end)` | this core's contiguous share of `[0, n)` |
| `barrier()` | wait until both cores arrive |
| `lock(i)`, `unlock(i)` | hardware spinlock `i` (0-7) |
| `fetch_add(i)`, `counter_set(i, v)` | atomic counter `i` (0-3), e.g. a work queue |
| `cycles()` | cycle counter, for timing |
| `print`, `println`, `print_int`, `print_hex` | console output |
| `SHARED` | marks data another core touches concurrently (`volatile`) |
| `NUM_WORKERS` | compile with `-DNUM_WORKERS=1` to time a one-core run |

### Rules

1. **Mark concurrently shared variables `SHARED`.** Otherwise the compiler may
   keep them in registers, and a spin-wait like `while (!flag);` never ends.
   Data that is only shared *across* a `barrier()` or a `lock()` does not
   need it, because those calls are compiler barriers.
2. **Protect read-modify-write of shared data** with `lock()` or use
   `fetch_add()`. `x = x + 1` from both cores loses updates
   (`lock_counter.c` shows it).
3. **Plain loads and stores are enough for flag and queue protocols** with a
   single writer per variable, because memory is sequentially consistent
   (`queue.c`, `peterson.c`).
4. **Mind false sharing.** Coherence works on 16-byte blocks, so two cores
   writing neighbouring words ping-pong the block between their caches.

## Example programs (`sw/programs`)

| Program | Shows |
|---|---|
| `hello.c` | core ids, console, barrier |
| `lock_counter.c` | lost updates without a lock, spinlock, atomic counter |
| `peterson.c` | mutual exclusion with plain loads/stores (needs sequential consistency) |
| `queue.c` | lock-free single-producer/single-consumer ring buffer |
| `array_sum.c` | static partitioning and a reduction |
| `matmul.c` | data-parallel 16x16 matrix multiply, checked against a serial pass |
| `work_queue.c` | dynamic load balancing with `fetch_add` (counting primes) |

Measured with `./sw/run.sh --speedup` (cycles for the parallel section):

| Program | 1 core | 2 cores | Speedup |
|---|---|---|---|
| array_sum | 8482 | 4253 | 1.99x |
| matmul | 56018 | 28135 | 1.99x |
| work_queue | 266377 | 136275 | 1.95x |
