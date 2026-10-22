// Single-producer/single-consumer ring buffer using only shared memory.
// Core 0 produces 1..N, core 1 consumes and sums them. No locks are needed:
// each index is written by one core only, and memory is sequentially consistent.
#include "parallel.h"

#define N    200
#define SIZE 8

SHARED int buf[SIZE];
SHARED unsigned head;   // next slot to write (producer only)
SHARED unsigned tail;   // next slot to read  (consumer only)

int main(void) {
    if (core_id() == 0) {
        for (int v = 1; v <= N; v++) {
            while (head - tail == SIZE)     // full
                ;
            buf[head % SIZE] = v;
            head = head + 1;
        }
        return 0;
    }

    int sum = 0;
    for (int n = 0; n < N; n++) {
        while (tail == head)                // empty
            ;
        sum += buf[tail % SIZE];
        tail = tail + 1;
    }
    print("consumer sum = "); print_int(sum); println("");
    return sum == N * (N + 1) / 2 ? 0 : 1;
}
