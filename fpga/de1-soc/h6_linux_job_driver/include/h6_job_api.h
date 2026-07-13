#ifndef H6_JOB_API_H
#define H6_JOB_API_H

#define H6_JOB_MAX_WORDS 32

struct h6_job {
    unsigned int count;
    unsigned int multiplier;
    unsigned int bias;
    unsigned int status;
    unsigned int completion;
    unsigned int event_count;
    unsigned int reserved[2];
    unsigned int input[H6_JOB_MAX_WORDS];
    unsigned int output[H6_JOB_MAX_WORDS];
};

/* _IOWR('H', 1, struct h6_job), fixed here for a libc-free client. */
#define H6_JOB_IOCTL_SUBMIT 0xc1204801u

#ifndef __KERNEL__
_Static_assert(sizeof(struct h6_job) == 0x120,
               "H6 job structure does not match the ioctl ABI");
#endif

#endif
