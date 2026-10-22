// Runtime for parallel (SPMD) programs on the dual-core system.
//
// Both cores run the same program. main() runs on both; use core_id() to
// split the work. Memory is shared and coherent (MSI) and, because the cores
// are in-order with no store buffer, sequentially consistent. Two rules:
//
//   1. Declare data that another core reads or writes concurrently SHARED
//      (volatile), or the compiler may keep it in a register.
//   2. Use lock()/unlock() for read-modify-write of shared data, barrier() to
//      separate phases, and fetch_add() to hand out work.
//
// Synchronization is provided by the memory-mapped sync unit (sync_unit.v),
// because the cores have no atomic instructions.

#ifndef PARALLEL_H
#define PARALLEL_H

#define SHARED volatile

// Number of cores that take part in the work (compile with -DNUM_WORKERS=1
// to time a single-core run). All cores still take part in barriers.
#ifndef NUM_WORKERS
#define NUM_WORKERS 2
#endif

#define SYNC_BASE     0x80000000u
#define SYNC_CORE_ID  0x00
#define SYNC_NCORES   0x04
#define SYNC_CYCLES   0x08
#define SYNC_PUTCHAR  0x10
#define SYNC_EXIT     0x14
#define SYNC_BARRIER  0x20
#define SYNC_LOCK(i)  (0x40 + 4 * (i))
#define SYNC_CTR(i)   (0x60 + 4 * (i))

#define NUM_LOCKS     8
#define NUM_COUNTERS  4

static inline unsigned sync_read(unsigned off) {
    return *(volatile unsigned *)(SYNC_BASE + off);
}
static inline void sync_write(unsigned off, unsigned v) {
    *(volatile unsigned *)(SYNC_BASE + off) = v;
}

// Stops the compiler from moving memory accesses across this point
#define compiler_barrier() __asm__ volatile("" ::: "memory")

static inline int core_id(void)      { return sync_read(SYNC_CORE_ID); }
static inline int num_cores(void)    { return sync_read(SYNC_NCORES); }
static inline unsigned cycles(void)  { return sync_read(SYNC_CYCLES); }

// Hardware spinlocks: reading a free lock claims it (returns 0)
static inline void lock(int i) {
    while (sync_read(SYNC_LOCK(i)) != 0)
        ;
    compiler_barrier();
}
static inline void unlock(int i) {
    compiler_barrier();
    sync_write(SYNC_LOCK(i), 0);
}

// Waits until every core has called barrier()
static inline void barrier(void) {
    compiler_barrier();
    unsigned gen = sync_read(SYNC_BARRIER);
    sync_write(SYNC_BARRIER, 1);
    while (sync_read(SYNC_BARRIER) == gen)
        ;
    compiler_barrier();
}

// Atomic counters: returns the old value and adds 1
static inline unsigned fetch_add(int i)              { return sync_read(SYNC_CTR(i)); }
static inline void counter_set(int i, unsigned v)    { sync_write(SYNC_CTR(i), v); }

// Splits [0, n) into NUM_WORKERS contiguous chunks; returns this core's chunk
static inline void my_range(int n, int *begin, int *end) {
    int id = core_id();
    if (id >= NUM_WORKERS) { *begin = *end = 0; return; }
    *begin = n * id / NUM_WORKERS;
    *end   = n * (id + 1) / NUM_WORKERS;
}

// Console (simulation): output is line-buffered per core
void print(const char *s);
void print_int(int v);
void print_hex(unsigned v);
void println(const char *s);

#endif
