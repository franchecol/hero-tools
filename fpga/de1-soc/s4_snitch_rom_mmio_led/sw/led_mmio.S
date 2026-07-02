// Documentation copy of the ROM program hardcoded in
// rtl/de1_s4_snitch_rom_mmio_led.sv.
//
// This file is not consumed by the S4 build yet. It exists so the hand-coded
// instruction words in the ROM can be read as normal RISC-V assembly.

.equ S4_MMIO_LED_ADDR, 0x40000000
.equ S4_LED_PATTERN,   0x155

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S4_MMIO_LED_ADDR)
    addi t1, zero, S4_LED_PATTERN
    sw   t1, 0(t0)

1:
    j    1b
