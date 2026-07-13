#include "h6_job_api.h"

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long usize;

#define SYS_EXIT 1
#define SYS_READ 3
#define SYS_WRITE 4
#define SYS_OPEN 5
#define SYS_CLOSE 6
#define SYS_IOCTL 54
#define SYS_GETUID32 199
#define O_RDONLY 0
#define O_RDWR 2
#define PAYLOAD_PATH "/tmp/h6_payload.bin"
#define DEVICE_PATH "/dev/snitch_job"
#define PAYLOAD_MAX 4096u

static u8 payload[PAYLOAD_MAX];

static long syscall0(long n) {
    register long r7 __asm__("r7") = n;
    register long r0 __asm__("r0");
    __asm__ volatile("svc 0" : "=r"(r0) : "r"(r7) : "memory");
    return r0;
}

static long syscall1(long n, long a0) {
    register long r7 __asm__("r7") = n;
    register long r0 __asm__("r0") = a0;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r7) : "memory");
    return r0;
}

static long syscall3(long n, long a0, long a1, long a2) {
    register long r7 __asm__("r7") = n;
    register long r0 __asm__("r0") = a0;
    register long r1 __asm__("r1") = a1;
    register long r2 __asm__("r2") = a2;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r7) : "memory");
    return r0;
}

static usize cstr_len(const char *s) {
    usize n = 0;
    while (s[n] != 0) ++n;
    return n;
}

static void write_all(int fd, const char *s) {
    usize len = cstr_len(s);
    while (len != 0) {
        long n = syscall3(SYS_WRITE, fd, (long)s, len);
        if (n <= 0) return;
        s += n;
        len -= (usize)n;
    }
}

static void write_hex32(const char *name, u32 value) {
    static const char hex[] = "0123456789abcdef";
    char buf[72];
    int i = 0;
    while (name[i] != 0) { buf[i] = name[i]; ++i; }
    buf[i++] = '='; buf[i++] = '0'; buf[i++] = 'x';
    for (int shift = 28; shift >= 0; shift -= 4) buf[i++] = hex[(value >> shift) & 0xfu];
    buf[i++] = '\n'; buf[i] = 0;
    write_all(1, buf);
}

static int load_payload(int device_fd) {
    int fd = (int)syscall3(SYS_OPEN, (long)PAYLOAD_PATH, O_RDONLY, 0);
    usize total = 0;
    long n;

    if (fd < 0) return 1;
    while (total < PAYLOAD_MAX) {
        n = syscall3(SYS_READ, fd, (long)(payload + total), PAYLOAD_MAX - total);
        if (n < 0) { syscall1(SYS_CLOSE, fd); return 1; }
        if (n == 0) break;
        total += (usize)n;
    }
    u8 extra;
    n = syscall3(SYS_READ, fd, (long)&extra, 1);
    syscall1(SYS_CLOSE, fd);
    if (n != 0 || total == 0 || (total & 3u) != 0) return 1;
    if (syscall3(SYS_WRITE, device_fd, (long)payload, total) != (long)total) return 1;
    write_hex32("H6_PAYLOAD_UPLOADS", 1);
    return 0;
}

static void clear_job(struct h6_job *job) {
    u32 *word = (u32 *)job;
    for (u32 i = 0; i < sizeof(*job) / sizeof(u32); ++i) word[i] = 0;
}

static int submit_and_check(int fd, struct h6_job *job, u32 index) {
    long rc = syscall3(SYS_IOCTL, fd, H6_JOB_IOCTL_SUBMIT, (long)job);
    if (rc != 0 || job->status != 0 || job->completion != 0x4834u ||
        job->event_count != index + 1u) return 1;
    for (u32 i = 0; i < job->count; ++i) {
        u32 expected = job->input[i] * job->multiplier + job->bias;
        if (job->output[i] != expected) return 1;
    }
    write_hex32(index == 0 ? "H6_JOB0_EVENT" : index == 1 ? "H6_JOB1_EVENT" : "H6_JOB2_EVENT",
                job->event_count);
    write_hex32(index == 0 ? "H6_JOB0_LAST_OUTPUT" : index == 1 ? "H6_JOB1_LAST_OUTPUT" : "H6_JOB2_LAST_OUTPUT",
                job->output[job->count - 1u]);
    write_all(1, index == 0 ? "H6_JOB0_PASS\n" : index == 1 ? "H6_JOB1_PASS\n" : "H6_JOB2_PASS\n");
    return 0;
}

static int run_h6(void) {
    struct h6_job job;
    int fd;

    write_hex32("H6_CLIENT_UID", (u32)syscall0(SYS_GETUID32));
    fd = (int)syscall3(SYS_OPEN, (long)DEVICE_PATH, O_RDWR, 0);
    if (fd < 0) {
        write_all(2, "open /dev/snitch_job failed\n");
        return 1;
    }
    if (load_payload(fd) != 0) goto fail;

    clear_job(&job);
    job.count = 3; job.multiplier = 2; job.bias = 1;
    job.input[0] = 2; job.input[1] = 4; job.input[2] = 8;
    if (submit_and_check(fd, &job, 0) != 0) goto fail;

    clear_job(&job);
    job.count = 6; job.multiplier = 5; job.bias = 11;
    job.input[0] = 1; job.input[1] = 3; job.input[2] = 7;
    job.input[3] = 16; job.input[4] = 256; job.input[5] = 1024;
    if (submit_and_check(fd, &job, 1) != 0) goto fail;

    clear_job(&job);
    job.count = 5; job.multiplier = 7; job.bias = 3;
    job.input[0] = 0; job.input[1] = 10; job.input[2] = 100;
    job.input[3] = 1000; job.input[4] = 65536;
    if (submit_and_check(fd, &job, 2) != 0) goto fail;

    syscall1(SYS_CLOSE, fd);
    write_all(1, "H6_LINUX_JOB_DRIVER_PASS\n");
    return 0;

fail:
    syscall1(SYS_CLOSE, fd);
    write_all(2, "H6_LINUX_JOB_DRIVER_FAIL\n");
    return 1;
}

void _start(void) {
    syscall1(SYS_EXIT, run_h6());
    syscall0(SYS_EXIT);
}
