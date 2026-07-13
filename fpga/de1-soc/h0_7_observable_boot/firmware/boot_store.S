.section .text.boot, "ax", @progbits
.globl _start
#ifndef SIGNATURE
#define SIGNATURE 0x5a5
#endif
_start:
    li      t0, 0x2000
    li      t1, SIGNATURE
    sw      t1, 0(t0)
1:
    j       1b
