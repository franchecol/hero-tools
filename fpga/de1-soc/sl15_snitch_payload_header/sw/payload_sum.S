// SL15 file-loaded Snitch payload.
//
// The ARM host loads this through a small SL15 payload image header. The FPGA
// hardware is still the SL13 Snitch-Lite IRQ-capable payload-loader bitstream.
// Keep this RV32E-friendly: use only x0-x15 registers.

.option norvc

.equ S15_RAM_BASE_ADDR,  0x00001000
.equ S15_MMIO_DONE_ADDR, 0x40000000

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S15_RAM_BASE_ADDR)
    addi t0, t0, %lo(S15_RAM_BASE_ADDR)

    lw   t1, 0(t0)
    lw   t2, 4(t0)
    add  a0, t1, t2
    sw   a0, 8(t0)

    lui  a1, %hi(S15_MMIO_DONE_ADDR)
    sw   a0, 0(a1)

done:
    j    done
