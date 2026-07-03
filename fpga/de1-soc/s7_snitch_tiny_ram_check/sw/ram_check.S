// S7 default software payload.
//
// This program proves that the Snitch data interface can perform a store/load
// sequence against tiny local FPGA RAM, not only an MMIO write.
// Keep this RV32E-friendly: use only x0-x15 registers.

.option norvc

.equ S7_RAM_BASE_ADDR,  0x00001000
.equ S7_MMIO_LED_ADDR,  0x40000000
.equ S7_TEST_VALUE,     0x0a5
.equ S7_PASS_PATTERN,   0x1a5
.equ S7_FAIL_PATTERN,   0x05a

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S7_RAM_BASE_ADDR)
    addi t0, t0, %lo(S7_RAM_BASE_ADDR)

    addi t1, zero, S7_TEST_VALUE
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t1, t2, fail

pass:
    lui  a0, %hi(S7_MMIO_LED_ADDR)
    addi a1, zero, S7_PASS_PATTERN
    sw   a1, 0(a0)
    j    done

fail:
    lui  a0, %hi(S7_MMIO_LED_ADDR)
    addi a1, zero, S7_FAIL_PATTERN
    sw   a1, 0(a0)

done:
    j    done
