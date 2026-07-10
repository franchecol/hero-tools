// Snitch-Lite Q1 MMIO-style store payload.
//
// This intentionally avoids snRuntime, DMA setup, OpenMP, libc, and custom
// Snitch instructions. It proves that the generated Snitch RTL can issue a
// normal store to a peripheral-style address.

.equ S1_MMIO_ADDR,  0x40000000
.equ S1_MMIO_VALUE, 0x0badcafe

.section .text.init, "ax", @progbits
.globl _start
_start:
    li   t0, S1_MMIO_ADDR
    li   t1, S1_MMIO_VALUE
    sw   t1, 0(t0)

    la   t2, observed_value
    sw   t1, 0(t2)

    // HTIF convention: (exit_code << 1) | 1.  Exit code 0 means pass.
    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)

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
.globl observed_value
observed_value:
    .word 0
