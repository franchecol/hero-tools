#ifndef H4_JOB_ABI_H
#define H4_JOB_ABI_H

#define H4_JOB_MAGIC             0x48344a42
#define H4_JOB_ABI_VERSION       1
#define H4_JOB_STATE_READY       1
#define H4_JOB_STATE_RUNNING     2
#define H4_JOB_STATE_DONE        3
#define H4_JOB_STATE_ERROR       0x80000000
#define H4_JOB_MAX_WORDS         32
#define H4_JOB_COMPLETION        0x4834

#define H4_JOB_MAGIC_OFFSET      0x00
#define H4_JOB_VERSION_OFFSET    0x04
#define H4_JOB_STATE_OFFSET      0x08
#define H4_JOB_STATUS_OFFSET     0x0c
#define H4_JOB_COUNT_OFFSET      0x10
#define H4_JOB_INPUT_OFFSET      0x14
#define H4_JOB_OUTPUT_OFFSET     0x18
#define H4_JOB_MULTIPLIER_OFFSET 0x1c
#define H4_JOB_BIAS_OFFSET       0x20
#define H4_JOB_BYTES             0x40

#define H4_INPUT_DATA_OFFSET     0x100
#define H4_OUTPUT_DATA_OFFSET    0x200

#define H4_STATUS_OK             0
#define H4_STATUS_BAD_MAGIC      1
#define H4_STATUS_BAD_VERSION    2
#define H4_STATUS_BAD_COUNT      3
#define H4_STATUS_BAD_LAYOUT     4

#ifndef __ASSEMBLER__
typedef unsigned int h4_u32;

struct h4_job_descriptor {
    h4_u32 magic;
    h4_u32 version;
    h4_u32 state;
    h4_u32 status;
    h4_u32 count;
    h4_u32 input_offset;
    h4_u32 output_offset;
    h4_u32 multiplier;
    h4_u32 bias;
    h4_u32 reserved[7];
};

_Static_assert(sizeof(struct h4_job_descriptor) == H4_JOB_BYTES,
               "H4 descriptor size does not match the ABI");
_Static_assert(__builtin_offsetof(struct h4_job_descriptor, state) == H4_JOB_STATE_OFFSET,
               "H4 state offset does not match the ABI");
_Static_assert(__builtin_offsetof(struct h4_job_descriptor, count) == H4_JOB_COUNT_OFFSET,
               "H4 count offset does not match the ABI");
_Static_assert(__builtin_offsetof(struct h4_job_descriptor, multiplier) == H4_JOB_MULTIPLIER_OFFSET,
               "H4 multiplier offset does not match the ABI");
_Static_assert(__builtin_offsetof(struct h4_job_descriptor, input_offset) == H4_JOB_INPUT_OFFSET,
               "H4 input offset does not match the ABI");
_Static_assert(__builtin_offsetof(struct h4_job_descriptor, output_offset) == H4_JOB_OUTPUT_OFFSET,
               "H4 output offset does not match the ABI");
#endif

#endif
