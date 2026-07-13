#include "h4_job_abi.h"

.section .text.boot, "ax", @progbits
.globl _start
_start:
    li      s0, 0x4000
    li      s6, 0x3000

wait_for_job:
    lw      t0, 0(s6)
    beqz    t0, wait_for_job

    lw      t0, H4_JOB_MAGIC_OFFSET(s0)
    li      t1, H4_JOB_MAGIC
    li      t6, H4_STATUS_BAD_MAGIC
    bne     t0, t1, job_error
    lw      t0, H4_JOB_VERSION_OFFSET(s0)
    li      t1, H4_JOB_ABI_VERSION
    li      t6, H4_STATUS_BAD_VERSION
    bne     t0, t1, job_error
    lw      s1, H4_JOB_COUNT_OFFSET(s0)
    li      t6, H4_STATUS_BAD_COUNT
    beqz    s1, job_error
    li      t0, H4_JOB_MAX_WORDS
    bltu    t0, s1, job_error
    li      t6, H4_STATUS_BAD_LAYOUT
    lw      t0, H4_JOB_INPUT_OFFSET(s0)
    li      t1, H4_INPUT_DATA_OFFSET
    bne     t0, t1, job_error
    lw      t0, H4_JOB_OUTPUT_OFFSET(s0)
    li      t1, H4_OUTPUT_DATA_OFFSET
    bne     t0, t1, job_error

    li      t0, H4_JOB_STATE_RUNNING
    sw      t0, H4_JOB_STATE_OFFSET(s0)
    sw      zero, H4_JOB_STATUS_OFFSET(s0)
    lw      t0, H4_JOB_INPUT_OFFSET(s0)
    add     s2, s0, t0
    lw      t0, H4_JOB_OUTPUT_OFFSET(s0)
    add     s3, s0, t0
    lw      s4, H4_JOB_MULTIPLIER_OFFSET(s0)
    lw      s5, H4_JOB_BIAS_OFFSET(s0)

transform_loop:
    lw      t0, 0(s2)
    mul     t1, t0, s4
    add     t1, t1, s5
    sw      t1, 0(s3)
    addi    s2, s2, 4
    addi    s3, s3, 4
    addi    s1, s1, -1
    bnez    s1, transform_loop
    li      t0, H4_JOB_STATE_DONE
    sw      t0, H4_JOB_STATE_OFFSET(s0)
    j       complete

job_error:
    sw      t6, H4_JOB_STATUS_OFFSET(s0)
    li      t0, H4_JOB_STATE_ERROR
    sw      t0, H4_JOB_STATE_OFFSET(s0)

complete:
    li      t0, 0x2000
    li      t1, H4_JOB_COMPLETION
    sw      t1, 0(t0)

wait_for_release:
    lw      t0, 0(s6)
    bnez    t0, wait_for_release
    j       wait_for_job
