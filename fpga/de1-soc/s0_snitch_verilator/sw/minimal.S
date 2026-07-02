// Minimal Snitch bare-metal payload for S0.
//
// This intentionally avoids snRuntime, DMA setup, OpenMP, libc, and custom
// Snitch instructions. It only proves that the generated Snitch RTL can fetch
// and execute a tiny normal RISC-V program, then report success through HTIF.

.section .text.init, "ax", @progbits
.globl _start
_start:
    li   t0, 0x1234
    addi t0, t0, 1

    la   t1, result
    sw   t0, 0(t1)

    // HTIF convention: (exit_code << 1) | 1.  Exit code 0 means pass.
    la   t1, tohost
    li   t0, 1
    sw   t0, 0(t1)

1:
    j    1b

.section .tohost, "aw", @progbits
.align 6
.globl tohost
tohost:
    .dword 0

.align 6
.globl fromhost
fromhost:
    .dword 0

.section .data, "aw", @progbits
.align 2
.globl result
result:
    .word 0
