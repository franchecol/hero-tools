// SL11 runtime-loaded Snitch payload.
//
// ARM Linux writes this instruction image into FPGA instruction memory before
// releasing Snitch from reset. Snitch reads ARG0/ARG1 from local RAM, stores
// their sum to RAM2, and reports the result through internal done/result MMIO.
// Keep this RV32E-friendly: use only x0-x15 registers.

.option norvc

.equ S11_RAM_BASE_ADDR,  0x00001000
.equ S11_MMIO_DONE_ADDR, 0x40000000

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S11_RAM_BASE_ADDR)
    addi t0, t0, %lo(S11_RAM_BASE_ADDR)

    lw   t1, 0(t0)
    lw   t2, 4(t0)
    add  a0, t1, t2
    sw   a0, 8(t0)

    lui  a1, %hi(S11_MMIO_DONE_ADDR)
    sw   a0, 0(a1)

done:
    j    done
