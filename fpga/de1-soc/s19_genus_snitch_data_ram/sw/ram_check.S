// RV32E store/load/compare payload for the Genus-generated Snitch core.

.option norvc

.equ RAM_BASE_ADDR,  0x00001000
.equ MMIO_LED_ADDR,  0x40000000
.equ TEST_VALUE,     0x0a5
.equ PASS_PATTERN,   0x1a5
.equ FAIL_PATTERN,   0x05a

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(RAM_BASE_ADDR)
    addi t0, t0, %lo(RAM_BASE_ADDR)
    addi t1, zero, TEST_VALUE
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t1, t2, fail

pass:
    lui  a0, %hi(MMIO_LED_ADDR)
    addi a1, zero, PASS_PATTERN
    sw   a1, 0(a0)
    j    done

fail:
    lui  a0, %hi(MMIO_LED_ADDR)
    addi a1, zero, FAIL_PATTERN
    sw   a1, 0(a0)

done:
    j    done
