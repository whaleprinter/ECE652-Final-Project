# Instructions right behind a multiply/divide must see its result.
    li a0, 7
    li a1, 6
    mul a2, a0, a1
    add x31, a2, x0     # immediately dependent: 42
    mul a3, a0, a0
    nop
    add x31, x31, a3    # one instruction later: +49 = 91
    li a4, 100
    divu a5, a4, a0
    nop
    nop
    add x31, x31, a5    # two later: +14 = 105
    mul a6, a1, a1
    nop
    nop
    nop
    add x31, x31, a6    # three later: +36 = 141
    li x30, 1
halt: j halt
