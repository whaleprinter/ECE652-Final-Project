#define SIZE 4

void main() {
    volatile int* A = (int*)0x2000;
    volatile int* B = (int*)0x2040;
    volatile int* C = (int*)0x2080;
    volatile int* init_flag = (int*)0x20C0;

    for(int i = 0; i < 16; i++) {
        A[i] = i + 1;                
        B[i] = (i % 5 == 0) ? 2 : 0; // diagonal of 2s
    }


    *init_flag = 1;

    // Compute top half of Matrix C (Rows 0 and 1)
    int checksum = 0;
    for(int i = 0; i < SIZE / 2; i++) {
        for(int j = 0; j < SIZE; j++) {
            int sum = 0;
            for(int k = 0; k < SIZE; k++) {
                sum += A[i * SIZE + k] * B[k * SIZE + j];
            }
            C[i * SIZE + j] = sum;
            checksum += sum;
        }
    }


    // Expected checksum for top half: 72
    __asm__ volatile ("mv x31, %0" : : "r" (checksum));
    __asm__ volatile ("li x30, 1");
    
    while(1); 
}