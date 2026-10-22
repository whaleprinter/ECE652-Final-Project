// Shared counter incremented by both cores, three ways:
//   unprotected  load/add/store races, so updates are lost
//   lock()       hardware spinlock around the read-modify-write
//   fetch_add()  hardware atomic counter
#include "parallel.h"

#define N 100

SHARED int racy;
SHARED int locked;

int main(void) {
    int id = core_id();

    for (int i = 0; i < N; i++)
        racy = racy + 1;

    for (int i = 0; i < N; i++) {
        lock(0);
        locked = locked + 1;
        unlock(0);
    }

    for (int i = 0; i < N; i++)
        fetch_add(1);

    barrier();

    if (id != 0)
        return 0;
    int atomic = fetch_add(1);
    print("unprotected: "); print_int(racy);   println(" (lost updates are expected)");
    print("lock():      "); print_int(locked); println("");
    print("fetch_add(): "); print_int(atomic); println("");
    return (locked == 2 * N && atomic == 2 * N) ? 0 : 1;
}
