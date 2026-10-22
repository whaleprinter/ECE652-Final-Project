// Both cores say hello, meet at a barrier, and core 0 reports.
#include "parallel.h"

int main(void) {
    int id = core_id();
    print("Hello from core ");
    print_int(id);
    print(" of ");
    print_int(num_cores());
    println("");

    barrier();

    if (id == 0)
        println("Both cores passed the barrier");
    return 0;
}
