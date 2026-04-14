void main() {
    int fact = 1;
    for(int i = 1; i <= 10; i++) {
        fact = fact * i;
    }

    // Write result to x31, then set done flag in x30
    __asm__ volatile ("mv x31, %0" : : "r" (fact));
    __asm__ volatile ("li x30, 1");
    
    while(1); 
}