// RV32E payload for the U1 Genus-generated Snitch core.

.option norvc

.equ S18_MMIO_LED_ADDR, 0x40000000
.equ S18_LED_PATTERN,   0x155

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S18_MMIO_LED_ADDR)
    addi t1, zero, S18_LED_PATTERN
    sw   t1, 0(t0)

1:
    j    1b
