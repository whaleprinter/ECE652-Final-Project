#define SIZE 4

void main() {
    volatile int* A = (int*)0x2000;
    volatile int* B = (int*)0x2040;
    volatile int* C = (int*)0x2080;
    volatile int* init_flag = (int*)0x20C0;


    while(*init_flag == 0);

    // Compute bottom half of Matrix C (Rows 2 and 3)
    int checksum = 0;
    for(int i = SIZE / 2; i < SIZE; i++) {
        for(int j = 0; j < SIZE; j++) {
            int sum = 0;
            for(int k = 0; k < SIZE; k++) {

                sum += A[i * SIZE + k] * B[k * SIZE + j];
            }
            C[i * SIZE + j] = sum;
            checksum += sum;
        }
    }

    // Expected result for bottom half: 200
    __asm__ volatile ("mv x31, %0" : : "r" (checksum));
    __asm__ volatile ("li x30, 1");
    
    while(1); 
}