typedef unsigned int u32;
typedef unsigned long usize;

#include "s11_payload_words.h"

#define NULL_PTR ((void *)0)

#define SYS_EXIT   1
#define SYS_WRITE  4
#define SYS_OPEN   5
#define SYS_CLOSE  6
#define SYS_MUNMAP 91
#define SYS_MMAP2  192

#define O_RDWR     2
#define PROT_READ  1
#define PROT_WRITE 2
#define MAP_SHARED 1

#define STDOUT_FD 1
#define STDERR_FD 2

#define LWH2F_BASE 0xff200000u
#define MAP_LEN    0x1000u

#define REG_ID            0x00u
#define REG_CONTROL       0x04u
#define REG_STATUS        0x08u
#define REG_RESULT        0x0cu
#define REG_START_COUNT   0x10u
#define REG_RUN_CYCLES    0x14u
#define REG_IMEM_CAPACITY 0x18u
#define REG_PAYLOAD_WORDS 0x1cu
#define REG_ARG0          0x20u
#define REG_ARG1          0x24u
#define REG_EXPECTED      0x28u
#define REG_RAM0          0x2cu
#define REG_RAM1          0x30u
#define REG_RAM2          0x34u
#define REG_PAYLOAD_BASE  0x100u

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
    __asm__ volatile(
        "svc 0"
        : "+r"(r0)
        : "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r7)
        : "memory");
    return r0;
}

static usize cstr_len(const char *s) {
    usize n = 0;
    while (s[n] != 0) {
        ++n;
    }
    return n;
}

static void write_all(int fd, const char *s) {
    usize len = cstr_len(s);
    while (len != 0) {
        long n = syscall3(SYS_WRITE, fd, (long)s, (long)len);
        if (n <= 0) {
            return;
        }
        s += n;
        len -= (usize)n;
    }
}

static void write_hex32(const char *name, u32 value) {
    char buf[40];
    const char hex[] = "0123456789abcdef";
    int i;

    for (i = 0; name[i] != 0; ++i) {
        buf[i] = name[i];
    }

    buf[i++] = ' ';
    buf[i++] = '=';
    buf[i++] = ' ';
    buf[i++] = '0';
    buf[i++] = 'x';

    for (int shift = 28; shift >= 0; shift -= 4) {
        buf[i++] = hex[(value >> shift) & 0xfu];
    }

    buf[i++] = '\n';
    buf[i] = 0;

    write_all(STDOUT_FD, buf);
}

static void write_hex_join(const char *tag, const char *suffix, u32 value) {
    char name[32];
    int p = 0;

    for (int i = 0; tag[i] != 0; ++i) {
        name[p++] = tag[i];
    }
    name[p++] = '_';
    for (int i = 0; suffix[i] != 0; ++i) {
        name[p++] = suffix[i];
    }
    name[p] = 0;

    write_hex32(name, value);
}

static u32 read_reg(volatile unsigned char *base, u32 offset) {
    return *(volatile u32 *)(base + offset);
}

static void write_reg(volatile unsigned char *base, u32 offset, u32 value) {
    *(volatile u32 *)(base + offset) = value;
}

static int load_payload(volatile unsigned char *regs) {
    u32 capacity = read_reg(regs, REG_IMEM_CAPACITY);
    write_hex32("IMEM_CAPACITY", capacity);

    if (S11_PAYLOAD_WORD_COUNT > capacity) {
        write_all(STDERR_FD, "payload too large for FPGA instruction memory\n");
        return 1;
    }

    for (u32 i = 0; i < S11_PAYLOAD_WORD_COUNT; ++i) {
        write_reg(regs, REG_PAYLOAD_BASE + (i * 4u), s11_payload_words[i]);
    }
    write_reg(regs, REG_PAYLOAD_WORDS, S11_PAYLOAD_WORD_COUNT);

    u32 payload_words = read_reg(regs, REG_PAYLOAD_WORDS);
    write_hex32("PAYLOAD_WORDS", payload_words);

    if (payload_words != S11_PAYLOAD_WORD_COUNT) {
        write_all(STDERR_FD, "payload word count mismatch\n");
        return 1;
    }

    for (u32 i = 0; i < S11_PAYLOAD_WORD_COUNT; ++i) {
        u32 readback = read_reg(regs, REG_PAYLOAD_BASE + (i * 4u));
        if (readback != s11_payload_words[i]) {
            write_all(STDERR_FD, "payload readback mismatch\n");
            return 1;
        }
    }

    return 0;
}

static int run_one(volatile unsigned char *regs, const char *tag, u32 arg0, u32 arg1) {
    u32 expected = arg0 + arg1;
    u32 status = 0;

    write_reg(regs, REG_ARG0, arg0);
    write_reg(regs, REG_ARG1, arg1);
    write_reg(regs, REG_EXPECTED, expected);
    write_reg(regs, REG_CONTROL, 0x1u);

    for (u32 i = 0; i < 50000000u; ++i) {
        status = read_reg(regs, REG_STATUS);
        if ((status & 0x1u) != 0) {
            break;
        }
    }

    u32 result = read_reg(regs, REG_RESULT);
    u32 start_count = read_reg(regs, REG_START_COUNT);
    u32 run_cycles = read_reg(regs, REG_RUN_CYCLES);
    u32 ram0 = read_reg(regs, REG_RAM0);
    u32 ram1 = read_reg(regs, REG_RAM1);
    u32 ram2 = read_reg(regs, REG_RAM2);

    write_hex_join(tag, "STATUS", status);
    write_hex_join(tag, "RESULT", result);
    write_hex_join(tag, "RAM0", ram0);
    write_hex_join(tag, "RAM1", ram1);
    write_hex_join(tag, "RAM2", ram2);
    write_hex32("START_COUNT", start_count);
    write_hex32("RUN_CYCLES ", run_cycles);

    if ((status & 0x1u) == 0) {
        write_all(STDERR_FD, "timeout waiting for done\n");
        return 1;
    }

    if ((status & 0x4u) == 0) {
        write_all(STDERR_FD, "pass bit not set\n");
        return 1;
    }

    if ((status & 0x8u) != 0) {
        write_all(STDERR_FD, "fail bit set\n");
        return 1;
    }

    if (result != expected || ram0 != arg0 || ram1 != arg1 || ram2 != expected) {
        write_all(STDERR_FD, "unexpected Snitch payload result\n");
        return 1;
    }

    return 0;
}

static int run_test(void) {
    int fd = (int)syscall3(SYS_OPEN, (long)"/dev/mem", O_RDWR, 0);
    if (fd < 0) {
        write_all(STDERR_FD, "open /dev/mem failed\n");
        return 1;
    }

    long mapped = syscall6(
        SYS_MMAP2,
        (long)NULL_PTR,
        MAP_LEN,
        PROT_READ | PROT_WRITE,
        MAP_SHARED,
        fd,
        LWH2F_BASE >> 12);

    if ((usize)mapped >= (usize)-4095) {
        write_all(STDERR_FD, "mmap2 failed\n");
        syscall1(SYS_CLOSE, fd);
        return 1;
    }

    volatile unsigned char *regs = (volatile unsigned char *)mapped;
    u32 id = read_reg(regs, REG_ID);
    write_hex32("ID          ", id);

    if (id != 0x53110001u) {
        write_all(STDERR_FD, "unexpected ID; check S11 bitstream, bridge enable, and address\n");
        syscall3(SYS_MUNMAP, mapped, MAP_LEN, 0);
        syscall1(SYS_CLOSE, fd);
        return 1;
    }

    write_reg(regs, REG_CONTROL, 0x2u);

    if (load_payload(regs) != 0) {
        syscall3(SYS_MUNMAP, mapped, MAP_LEN, 0);
        syscall1(SYS_CLOSE, fd);
        return 1;
    }

    if (run_one(regs, "RUN0", 0x00000100u, 0x000000a5u) != 0) {
        syscall3(SYS_MUNMAP, mapped, MAP_LEN, 0);
        syscall1(SYS_CLOSE, fd);
        return 1;
    }

    if (run_one(regs, "RUN1", 0x00000200u, 0x00000055u) != 0) {
        syscall3(SYS_MUNMAP, mapped, MAP_LEN, 0);
        syscall1(SYS_CLOSE, fd);
        return 1;
    }

    syscall3(SYS_MUNMAP, mapped, MAP_LEN, 0);
    syscall1(SYS_CLOSE, fd);

    write_all(STDOUT_FD, "PASS\n");
    return 0;
}

void _start(void) {
    syscall1(SYS_EXIT, run_test());
    syscall0(SYS_EXIT);
}
