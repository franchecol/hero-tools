// S8 default software payload.
//
// The host starts the Snitch core through JTAG-visible control registers.
// Snitch then stores to tiny local RAM, loads back, checks the value, and
// reports pass/fail through the internal result MMIO register.
// Keep this RV32E-friendly: use only x0-x15 registers.

.option norvc

.equ S8_RAM_BASE_ADDR,  0x00001000
.equ S8_MMIO_DONE_ADDR, 0x40000000
.equ S8_TEST_VALUE,     0x0a5
.equ S8_PASS_PATTERN,   0x1a5
.equ S8_FAIL_PATTERN,   0x05a

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S8_RAM_BASE_ADDR)
    addi t0, t0, %lo(S8_RAM_BASE_ADDR)

    addi t1, zero, S8_TEST_VALUE
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t1, t2, fail

pass:
    lui  a0, %hi(S8_MMIO_DONE_ADDR)
    addi a1, zero, S8_PASS_PATTERN
    sw   a1, 0(a0)
    j    done

fail:
    lui  a0, %hi(S8_MMIO_DONE_ADDR)
    addi a1, zero, S8_FAIL_PATTERN
    sw   a1, 0(a0)

done:
    j    done
