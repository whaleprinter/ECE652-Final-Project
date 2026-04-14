void main() {

    int data[5];
    

    data[0] = 10;
    data[1] = 20;
    data[2] = 30;
    data[3] = 40;
    data[4] = 50;

    int sum = 0;
    for(int i = 0; i < 5; i++) {
        sum += data[i]; 
    }

    // Write result to x31, then set done flag in x30
    __asm__ volatile ("mv x31, %0" : : "r" (sum));
    __asm__ volatile ("li x30, 1");
    
    while(1); 
}