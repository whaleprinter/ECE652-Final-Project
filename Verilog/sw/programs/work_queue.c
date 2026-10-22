// Dynamic load balancing: count the primes below 1024 in 32-number chunks.
// Chunks near the top cost more, so instead of a static split each core
// takes the next chunk from a hardware fetch_add counter.
#include "parallel.h"

#define LIMIT  1024
#define CHUNK  32

SHARED int total;

static int is_prime(int n) {
    if (n < 2)
        return 0;
    for (int d = 2; d * d <= n; d++)
        if (n % d == 0)
            return 0;
    return 1;
}

int main(void) {
    int id = core_id();
    if (id == 0)
        counter_set(0, 0);
    barrier();

    int mine = 0, chunks = 0;
    if (id < NUM_WORKERS) {
        for (;;) {
            int c = fetch_add(0);
            if (c * CHUNK >= LIMIT)
                break;
            for (int n = c * CHUNK; n < (c + 1) * CHUNK; n++)
                mine += is_prime(n);
            chunks++;
        }
    }
    lock(0);
    total = total + mine;
    unlock(0);

    print("took "); print_int(chunks); println(" chunks");
    barrier();

    if (id != 0)
        return 0;
    print("primes below "); print_int(LIMIT); print(": "); print_int(total); println("");
    return total == 172 ? 0 : 1;
}
