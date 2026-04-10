addi x8, x0, 0 # Flag variable

addi x10, x0, 0
addi x11, x0, 0
addi x12, x0, 0
addi x13, x0, 0


data_ready: 

    lw x8, 16(x0) # Load flag from address 16
    beq x8, x0, data_ready # Wait until flag is set to 1

    lw x10, 0(x0) # Read data from address 0
    lw x11, 4(x0) # Read data from address 4
    lw x12, 8(x0) # Read data from address 8
    lw x13, 12(x0) # Read data from address 12

    add x14, x10, x11 # Add the first two numbers
    add x15, x12, x13 # Add the last two numbers
    add x16, x14, x15 # Add the two sums together
  
    