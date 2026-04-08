	.file	"core0_program.c"
	.option nopic
	.attribute arch, "rv32i2p1"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32
	sw	ra,28(sp)
	sw	s0,24(sp)
	addi	s0,sp,32
	li	a5,4096
	sw	a5,-20(s0)
	li	a5,4096
	addi	a5,a5,4
	sw	a5,-24(s0)
	lw	a5,-24(s0)
	sw	zero,0(a5)
	lw	a5,-20(s0)
	li	a4,-559038464
	addi	a4,a4,-273
	sw	a4,0(a5)
	lw	a5,-24(s0)
	li	a4,1
	sw	a4,0(a5)
.L2:
	j	.L2
	.size	main, .-main
	.ident	"GCC: (g1b306039a) 15.1.0"
	.section	.note.GNU-stack,"",@progbits
