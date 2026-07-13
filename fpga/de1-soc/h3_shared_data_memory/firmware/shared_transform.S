.section .text.boot, "ax", @progbits
.globl _start
_start:
    li      t0, 0x4000
    li      t1, 0x4040
    li      t2, 4

1:
    lw      t3, 0(t0)
    slli    t4, t3, 1
    add     t4, t4, t3
    addi    t4, t4, 7
    sw      t4, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    addi    t2, t2, -1
    bnez    t2, 1b

    li      t0, 0x2000
    li      t1, 0x4833
    sw      t1, 0(t0)
2:
    j       2b
