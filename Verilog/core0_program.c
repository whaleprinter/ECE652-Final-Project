// Hardcode the physical addresses we want to share
// We use addresses we know are valid based on your Verilog testbenches
#define SHARED_DATA_ADDR 0x00001000
#define SYNC_FLAG_ADDR   0x00001004

int main() {
    // Cast the hardcoded addresses to volatile integer pointers
    volatile int *shared_data = (volatile int *)SHARED_DATA_ADDR;
    volatile int *sync_flag   = (volatile int *)SYNC_FLAG_ADDR;

    // 1. Initialize the synchronization flag to 0
    // L1_CC Action: Write Miss (I -> IM_D -> M)
    *sync_flag = 0;

    // 2. Write the actual payload into the shared memory space
    // L1_CC Action: Write Hit (M remains M)
    *shared_data = 0xDEADBEEF;

    // 3. Set the flag to 1 to signal Core 1 that the data is ready
    // L1_CC Action: Write Hit (M remains M)
    *sync_flag = 1;

    // Infinite loop to halt the core when finished
    while(1) {
        // Do nothing
    }

    return 0;
}