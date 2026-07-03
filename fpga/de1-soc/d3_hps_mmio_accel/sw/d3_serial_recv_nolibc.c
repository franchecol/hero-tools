typedef unsigned long usize;

#define SYS_EXIT  1
#define SYS_READ  3
#define SYS_WRITE 4
#define SYS_OPEN  5
#define SYS_CLOSE 6

#define O_WRONLY 1
#define O_CREAT  0100
#define O_TRUNC  01000

#define STDIN_FD  0
#define STDOUT_FD 1
#define STDERR_FD 2

static unsigned char buf[4096];

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

static int parse_u32(const char *s, usize *out) {
    usize value = 0;

    if (*s == 0) {
        return 0;
    }

    while (*s != 0) {
        if (*s < '0' || *s > '9') {
            return 0;
        }
        value = value * 10u + (usize)(*s - '0');
        ++s;
    }

    *out = value;
    return 1;
}

static int copy_exact(const char *path, usize total) {
    int out = (int)syscall3(SYS_OPEN, (long)path, O_WRONLY | O_CREAT | O_TRUNC, 0755);
    if (out < 0) {
        write_all(STDERR_FD, "open output failed\n");
        return 1;
    }

    usize remaining = total;
    while (remaining != 0) {
        usize want = remaining;
        if (want > sizeof(buf)) {
            want = sizeof(buf);
        }

        long got = syscall3(SYS_READ, STDIN_FD, (long)buf, (long)want);
        if (got <= 0) {
            write_all(STDERR_FD, "read failed\n");
            syscall1(SYS_CLOSE, out);
            return 1;
        }

        usize written = 0;
        while (written < (usize)got) {
            long n = syscall3(SYS_WRITE, out, (long)(buf + written), got - (long)written);
            if (n <= 0) {
                write_all(STDERR_FD, "write failed\n");
                syscall1(SYS_CLOSE, out);
                return 1;
            }
            written += (usize)n;
        }

        remaining -= (usize)got;
    }

    syscall1(SYS_CLOSE, out);
    write_all(STDOUT_FD, "recv ok\n");
    return 0;
}

void entry_from_stack(usize *sp) __attribute__((used, noinline));
void entry_from_stack(usize *sp) {
    int argc = (int)sp[0];
    char **argv = (char **)&sp[1];

    if (argc != 3) {
        write_all(STDERR_FD, "usage: d3_serial_recv <output> <bytes>\n");
        syscall1(SYS_EXIT, 2);
    }

    usize total = 0;
    if (!parse_u32(argv[2], &total)) {
        write_all(STDERR_FD, "invalid byte count\n");
        syscall1(SYS_EXIT, 2);
    }

    syscall1(SYS_EXIT, copy_exact(argv[1], total));
    syscall0(SYS_EXIT);
}

void _start(void) __attribute__((naked));
void _start(void) {
    __asm__ volatile(
        "mov r0, sp\n"
        "b entry_from_stack\n");
}
