// S10 software payload.
//
// The ARM host writes ARG0/ARG1/EXPECTED through HPS MMIO registers before
// start. Hardware copies ARG0/ARG1 into Snitch local RAM. Snitch reads those
// RAM words, computes ARG0 + ARG1, stores the result to RAM2, and reports the
// result through the internal done/result MMIO register.
// Keep this RV32E-friendly: use only x0-x15 registers.

.option norvc

.equ S10_RAM_BASE_ADDR,  0x00001000
.equ S10_MMIO_DONE_ADDR, 0x40000000

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S10_RAM_BASE_ADDR)
    addi t0, t0, %lo(S10_RAM_BASE_ADDR)

    lw   t1, 0(t0)
    lw   t2, 4(t0)
    add  a0, t1, t2
    sw   a0, 8(t0)

    lui  a1, %hi(S10_MMIO_DONE_ADDR)
    sw   a0, 0(a1)

done:
    j    done
