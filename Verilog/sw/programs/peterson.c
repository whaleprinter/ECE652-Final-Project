// Mutual exclusion with Peterson's algorithm, using only ordinary loads and
// stores to shared memory: no sync-unit locks. It is only correct on
// sequentially consistent memory, so it is a good end-to-end check of the
// coherence protocol.
#include "parallel.h"

#define N 100

SHARED int flag[2];
SHARED int turn;
SHARED int counter;

static void enter(int me) {
    int other = 1 - me;
    flag[me] = 1;
    turn = other;
    while (flag[other] && turn == other)
        ;
}

static void leave(int me) {
    flag[me] = 0;
}

int main(void) {
    int me = core_id();
    for (int i = 0; i < N; i++) {
        enter(me);
        counter = counter + 1;
        leave(me);
    }
    barrier();
    if (me == 0) {
        print("Peterson counter: "); print_int(counter); println("");
    }
    return counter == 2 * N ? 0 : 1;
}
