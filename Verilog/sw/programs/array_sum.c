// Parallel reduction: each core fills and sums its half of a 1024-element
// array (4 KB, the size of one L1D), then the partial sums are combined.
#include "parallel.h"

#define N 1024

int data[N];
SHARED int partial[2];

int main(void) {
    int id = core_id();
    int begin, end;
    my_range(N, &begin, &end);

    barrier();
    unsigned t0 = cycles();

    int sum = 0;
    for (int i = begin; i < end; i++) {
        data[i] = i;
        sum += data[i];
    }
    partial[id] = sum;

    barrier();
    unsigned t1 = cycles();

    if (id != 0)
        return 0;
    int total = partial[0] + partial[1];
    print("sum = "); print_int(total);
    print(", workers = "); print_int(NUM_WORKERS);
    print(", cycles = "); print_int(t1 - t0); println("");
    return total == N * (N - 1) / 2 ? 0 : 1;
}
