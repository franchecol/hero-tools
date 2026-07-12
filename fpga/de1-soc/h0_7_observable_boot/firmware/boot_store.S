.section .text.boot, "ax", @progbits
.globl _start
_start:
    li      t0, 0x2000
    li      t1, 0x5a5
    sw      t1, 0(t0)
1:
    j       1b
