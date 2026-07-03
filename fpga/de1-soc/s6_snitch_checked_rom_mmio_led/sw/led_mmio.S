// S6 default software payload.
//
// This file is assembled into an ELF, converted to raw instruction words, and
// included in the FPGA RTL as a checked generated ROM. Keep this RV32E-friendly:
// use only x0-x15 registers.

.option norvc

.equ S6_MMIO_LED_ADDR, 0x40000000
.equ S6_LED_PATTERN,   0x155

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S6_MMIO_LED_ADDR)
    addi t1, zero, S6_LED_PATTERN
    sw   t1, 0(t0)

1:
    j    1b
