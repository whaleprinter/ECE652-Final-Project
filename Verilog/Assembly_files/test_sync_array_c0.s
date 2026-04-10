addi x8, x0, 0 # Flag variable 

addi x10, x0, 10
addi x11, x0, 20
addi x12, x0, 30
addi x13, x0, 40

sw x10, 0(x0) # Write 10 to address 0
sw x11, 4(x0) # Write 20 to address 4
sw x12, 8(x0) # Write 30 to address 8
sw x13, 12(x0) # Write 40 to address 12

# Set flag to 1 to indicate data is ready
addi x8, x0, 1
sw x8, 16(x0) # Write flag to address 16


