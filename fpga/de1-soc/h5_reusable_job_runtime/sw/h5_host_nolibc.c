#include "h4_job_abi.h"

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long usize;

#define SYS_EXIT 1
#define SYS_READ 3
#define SYS_WRITE 4
#define SYS_OPEN 5
#define SYS_CLOSE 6
#define SYS_MUNMAP 91
#define SYS_POLL 168
#define SYS_MMAP2 192

#define O_RDONLY 0
#define O_RDWR 2
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1
#define POLLIN 0x0001

#define LWH2F_BASE 0xff200000u
#define MAP_LEN 0x3000u
#define BOOT_OFFSET 0x1000u
#define DATA_OFFSET 0x2000u
#define BOOT_BYTES 4096u
#define DATA_BYTES 4096u

#define REG_ID 0x00u
#define REG_CONTROL 0x04u
#define REG_STATUS 0x08u
#define REG_RESULT 0x10u
#define REG_IRQ_ENABLE 0x14u
#define REG_IRQ_PENDING 0x18u
#define REG_BOOT_BASE 0x1cu
#define REG_BOOT_SIZE 0x20u
#define REG_DATA_BASE 0x24u
#define REG_DATA_SIZE 0x28u

#define STATUS_RESULT_VALID (1u << 4)
#define BLOCK_ID 0x48300005u
#define PAYLOAD_PATH "/tmp/h5_payload.bin"
#define IRQ_PATH "/dev/snitch_lite_irq"
#define JOB_COUNT 3u
#define MAX_TEST_WORDS 6u

struct snitch_irq_event {
    u32 count;
    u32 status;
};

struct pollfd {
    int fd;
    short events;
    short revents;
};

struct job_spec {
    u32 count;
    u32 multiplier;
    u32 bias;
    u32 input[MAX_TEST_WORDS];
};

static const struct job_spec jobs[JOB_COUNT] = {
    {3u, 2u, 1u, {2u, 4u, 8u, 0u, 0u, 0u}},
    {6u, 5u, 11u, {1u, 3u, 7u, 16u, 256u, 1024u}},
    {5u, 7u, 3u, {0u, 10u, 100u, 1000u, 65536u, 0u}},
};
static u8 payload[BOOT_BYTES];

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

static long syscall6(long n, long a0, long a1, long a2, long a3, long a4, long a5) {
    register long r7 __asm__("r7") = n;
    register long r0 __asm__("r0") = a0;
    register long r1 __asm__("r1") = a1;
    register long r2 __asm__("r2") = a2;
    register long r3 __asm__("r3") = a3;
    register long r4 __asm__("r4") = a4;
    register long r5 __asm__("r5") = a5;
    __asm__ volatile("svc 0" : "+r"(r0)
                     : "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r7)
                     : "memory");
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
        long n = syscall3(SYS_WRITE, fd, (long)s, (long)len);
        if (n <= 0) return;
        s += n;
        len -= (usize)n;
    }
}

static void write_hex32(const char *name, u32 value) {
    static const char hex[] = "0123456789abcdef";
    char buf[80];
    int i = 0;
    while (name[i] != 0) { buf[i] = name[i]; ++i; }
    buf[i++] = '='; buf[i++] = '0'; buf[i++] = 'x';
    for (int shift = 28; shift >= 0; shift -= 4) buf[i++] = hex[(value >> shift) & 0xfu];
    buf[i++] = '\n'; buf[i] = 0;
    write_all(1, buf);
}

static void write_job_hex(const char *field, u32 job, u32 value) {
    char name[40];
    int p = 0;
    name[p++] = 'J'; name[p++] = 'O'; name[p++] = 'B';
    name[p++] = (char)('0' + job); name[p++] = '_';
    for (int i = 0; field[i] != 0; ++i) name[p++] = field[i];
    name[p] = 0;
    write_hex32(name, value);
}

static u32 mmio_read(volatile u8 *base, u32 offset) {
    return *(volatile u32 *)(base + offset);
}

static void mmio_write(volatile u8 *base, u32 offset, u32 value) {
    *(volatile u32 *)(base + offset) = value;
}

static void io_barrier(void) {
    __asm__ volatile("dmb sy" ::: "memory");
}

static int read_payload(u32 *size_out) {
    int fd = (int)syscall3(SYS_OPEN, (long)PAYLOAD_PATH, O_RDONLY, 0);
    if (fd < 0) return 1;
    usize total = 0;
    while (total < BOOT_BYTES) {
        long n = syscall3(SYS_READ, fd, (long)(payload + total), BOOT_BYTES - total);
        if (n < 0) { syscall1(SYS_CLOSE, fd); return 1; }
        if (n == 0) break;
        total += (usize)n;
    }
    u8 extra;
    long extra_count = syscall3(SYS_READ, fd, (long)&extra, 1);
    syscall1(SYS_CLOSE, fd);
    if (extra_count != 0 || total == 0 || (total & 3u) != 0) return 1;
    *size_out = (u32)total;
    return 0;
}

static int verify_capabilities(volatile u8 *base) {
    return mmio_read(base, REG_ID) != BLOCK_ID ||
           mmio_read(base, REG_BOOT_BASE) != BOOT_OFFSET ||
           mmio_read(base, REG_BOOT_SIZE) != BOOT_BYTES ||
           mmio_read(base, REG_DATA_BASE) != DATA_OFFSET ||
           mmio_read(base, REG_DATA_SIZE) != DATA_BYTES;
}

static void upload_program(volatile u8 *base, u32 payload_size) {
    volatile u32 *boot = (volatile u32 *)(base + BOOT_OFFSET);
    for (u32 i = 0; i < payload_size / 4u; ++i) {
        u32 off = i * 4u;
        boot[i] = (u32)payload[off] | ((u32)payload[off + 1u] << 8) |
                  ((u32)payload[off + 2u] << 16) | ((u32)payload[off + 3u] << 24);
    }
}

static int wait_result_clear(volatile u8 *base) {
    for (u32 i = 0; i < 1000000u; ++i) {
        if ((mmio_read(base, REG_STATUS) & STATUS_RESULT_VALID) == 0) return 0;
    }
    return 1;
}

static void prepare_job(volatile u8 *base, const struct job_spec *spec) {
    volatile struct h4_job_descriptor *job =
        (volatile struct h4_job_descriptor *)(base + DATA_OFFSET);
    volatile u32 *input = (volatile u32 *)(base + DATA_OFFSET + H4_INPUT_DATA_OFFSET);
    volatile u32 *output = (volatile u32 *)(base + DATA_OFFSET + H4_OUTPUT_DATA_OFFSET);

    job->magic = H4_JOB_MAGIC;
    job->version = H4_JOB_ABI_VERSION;
    job->state = H4_JOB_STATE_READY;
    job->status = H4_STATUS_OK;
    job->count = spec->count;
    job->input_offset = H4_INPUT_DATA_OFFSET;
    job->output_offset = H4_OUTPUT_DATA_OFFSET;
    job->multiplier = spec->multiplier;
    job->bias = spec->bias;
    for (u32 i = 0; i < 7u; ++i) job->reserved[i] = 0;
    for (u32 i = 0; i < spec->count; ++i) {
        input[i] = spec->input[i];
        output[i] = 0;
    }
}

static int verify_job(volatile u8 *base, const struct job_spec *spec, u32 index) {
    volatile struct h4_job_descriptor *job =
        (volatile struct h4_job_descriptor *)(base + DATA_OFFSET);
    volatile u32 *output = (volatile u32 *)(base + DATA_OFFSET + H4_OUTPUT_DATA_OFFSET);

    write_job_hex("STATE", index, job->state);
    write_job_hex("STATUS", index, job->status);
    if (job->state != H4_JOB_STATE_DONE || job->status != H4_STATUS_OK) return 1;
    for (u32 i = 0; i < spec->count; ++i) {
        u32 expected = spec->input[i] * spec->multiplier + spec->bias;
        if (output[i] != expected) return 1;
    }
    write_job_hex("LAST_OUTPUT", index, output[spec->count - 1u]);
    return 0;
}

static int submit_job(volatile u8 *base, int irq_fd, const struct job_spec *spec,
                      u32 index, u32 expected_event) {
    struct snitch_irq_event event;
    struct pollfd pfd = {irq_fd, POLLIN, 0};

    mmio_write(base, REG_CONTROL, 0);
    if (wait_result_clear(base) != 0) return 1;
    prepare_job(base, spec);
    mmio_write(base, REG_IRQ_PENDING, 1);
    io_barrier();
    mmio_write(base, REG_CONTROL, 1);

    long poll_rc = syscall3(SYS_POLL, (long)&pfd, 1, 5000);
    if (poll_rc != 1 || (pfd.revents & POLLIN) == 0) goto fail;
    if (syscall3(SYS_READ, irq_fd, (long)&event, sizeof(event)) != (long)sizeof(event)) goto fail;
    write_job_hex("IRQ_EVENT", index, event.count);
    if (event.count != expected_event || mmio_read(base, REG_RESULT) != H4_JOB_COMPLETION) goto fail;

    mmio_write(base, REG_CONTROL, 0);
    if (wait_result_clear(base) != 0 || verify_job(base, spec, index) != 0) return 1;
    write_all(1, index == 0 ? "H5_JOB0_PASS\n" : index == 1 ? "H5_JOB1_PASS\n" : "H5_JOB2_PASS\n");
    return 0;

fail:
    mmio_write(base, REG_CONTROL, 0);
    return 1;
}

static int run_h5(void) {
    u32 payload_size;
    if (read_payload(&payload_size) != 0) {
        write_all(2, "H5 payload read failed\n");
        return 1;
    }
    int irq_fd = (int)syscall3(SYS_OPEN, (long)IRQ_PATH, O_RDONLY, 0);
    int mem_fd = (int)syscall3(SYS_OPEN, (long)"/dev/mem", O_RDWR, 0);
    if (irq_fd < 0 || mem_fd < 0) return 1;

    long mapped = syscall6(SYS_MMAP2, 0, MAP_LEN, PROT_READ | PROT_WRITE,
                           MAP_SHARED, mem_fd, LWH2F_BASE >> 12);
    if ((usize)mapped >= (usize)-4095) return 1;
    volatile u8 *base = (volatile u8 *)mapped;
    int rc = 1;

    if (verify_capabilities(base) != 0) goto out;
    mmio_write(base, REG_CONTROL, 0);
    if (wait_result_clear(base) != 0) goto out;
    upload_program(base, payload_size);
    write_hex32("H5_PAYLOAD_UPLOADS", 1);
    mmio_write(base, REG_IRQ_PENDING, 1);
    mmio_write(base, REG_IRQ_ENABLE, 1);

    for (u32 i = 0; i < JOB_COUNT; ++i) {
        if (submit_job(base, irq_fd, &jobs[i], i, i + 1u) != 0) goto out;
    }
    write_all(1, "H5_REUSABLE_RUNTIME_PASS\n");
    rc = 0;

out:
    mmio_write(base, REG_CONTROL, 0);
    mmio_write(base, REG_IRQ_ENABLE, 0);
    syscall3(SYS_MUNMAP, mapped, MAP_LEN, 0);
    syscall1(SYS_CLOSE, mem_fd);
    syscall1(SYS_CLOSE, irq_fd);
    if (rc != 0) write_all(2, "H5_REUSABLE_RUNTIME_FAIL\n");
    return rc;
}

void _start(void) {
    syscall1(SYS_EXIT, run_h5());
    syscall0(SYS_EXIT);
}
