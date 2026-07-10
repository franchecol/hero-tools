// SL13 file-loaded Snitch payload.
//
// ARM Linux reads the compiled binary form of this file from /tmp/s13_payload.bin
// and writes it into the SL13 FPGA instruction-memory window at runtime.
// Keep this RV32E-friendly: use only x0-x15 registers.

.option norvc

.equ S13_RAM_BASE_ADDR,  0x00001000
.equ S13_MMIO_DONE_ADDR, 0x40000000

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S13_RAM_BASE_ADDR)
    addi t0, t0, %lo(S13_RAM_BASE_ADDR)

    lw   t1, 0(t0)
    lw   t2, 4(t0)
    add  a0, t1, t2
    sw   a0, 8(t0)

    lui  a1, %hi(S13_MMIO_DONE_ADDR)
    sw   a0, 0(a1)

done:
    j    done
