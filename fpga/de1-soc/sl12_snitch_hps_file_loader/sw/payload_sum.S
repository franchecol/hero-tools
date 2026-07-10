// SL12 file-loaded Snitch payload.
//
// ARM Linux reads the compiled binary form of this file from /tmp/s12_payload.bin
// and writes it into the SL11 FPGA instruction-memory window at runtime.
// Keep this RV32E-friendly: use only x0-x15 registers.

.option norvc

.equ S12_RAM_BASE_ADDR,  0x00001000
.equ S12_MMIO_DONE_ADDR, 0x40000000

.section .text.init, "ax", @progbits
.globl _start
_start:
    lui  t0, %hi(S12_RAM_BASE_ADDR)
    addi t0, t0, %lo(S12_RAM_BASE_ADDR)

    lw   t1, 0(t0)
    lw   t2, 4(t0)
    add  a0, t1, t2
    sw   a0, 8(t0)

    lui  a1, %hi(S12_MMIO_DONE_ADDR)
    sw   a0, 0(a1)

done:
    j    done
