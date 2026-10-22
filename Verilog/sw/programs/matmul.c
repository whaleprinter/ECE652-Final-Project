// Parallel matrix multiply C = A * B (16x16 ints), split by rows.
// Core 0 checks every element against a serial recomputation afterwards.
#include "parallel.h"

#define D 16

int A[D][D], B[D][D], C[D][D];

int main(void) {
    int id = core_id();
    int begin, end;
    my_range(D, &begin, &end);

    // Each core initializes its rows
    for (int i = begin; i < end; i++)
        for (int j = 0; j < D; j++) {
            A[i][j] = i + j;
            B[i][j] = i - j;
        }

    barrier();
    unsigned t0 = cycles();

    for (int i = begin; i < end; i++)
        for (int j = 0; j < D; j++) {
            int s = 0;
            for (int k = 0; k < D; k++)
                s += A[i][k] * B[k][j];
            C[i][j] = s;
        }

    barrier();
    unsigned t1 = cycles();

    if (id != 0)
        return 0;
    int errors = 0;
    for (int i = 0; i < D; i++)
        for (int j = 0; j < D; j++) {
            int s = 0;
            for (int k = 0; k < D; k++)
                s += (i + k) * (k - j);
            if (C[i][j] != s)
                errors++;
        }
    print("matmul "); print_int(D); print("x"); print_int(D);
    print(": workers = "); print_int(NUM_WORKERS);
    print(", cycles = "); print_int(t1 - t0);
    print(", errors = "); print_int(errors); println("");
    return errors;
}
