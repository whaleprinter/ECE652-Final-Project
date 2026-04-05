#define SHARED_DATA_ADDR 0x00001000
#define SYNC_FLAG_ADDR   0x00001004

int main() {
    volatile int *shared_data = (volatile int *)SHARED_DATA_ADDR;
    volatile int *sync_flag   = (volatile int *)SYNC_FLAG_ADDR;
    
    int local_copy = 0;

    // 1. Poll the synchronization flag
    // First loop iteration: 
    //   L1_CC Action: Read Miss (I -> IS_D -> S). 
    //   Arbiter: Snoops Core 0. Core 0 pushes dirty data across the C2C link!
    // Subsequent loop iterations (while flag is still 0):
    //   L1_CC Action: Read Hit (S remains S). Super fast, no bus traffic.
    while (*sync_flag == 0) {
        // Wait patiently
    }

    // 2. The flag is now 1! Read the payload.
    // L1_CC Action: Read Miss (I -> IS_D -> S).
    // Arbiter: Snoops Core 0. Core 0 pushes 0xDEADBEEF across the C2C link!
    local_copy = *shared_data;

    // Infinite loop to halt the core when finished
    while(1) {
        // Do nothing
    }

    return 0;
}