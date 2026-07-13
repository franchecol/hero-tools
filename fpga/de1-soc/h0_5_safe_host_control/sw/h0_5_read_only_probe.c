typedef unsigned int u32;
typedef unsigned long usize;

#define SYS_EXIT   1
#define SYS_WRITE  4
#define SYS_OPEN   5
#define SYS_CLOSE  6
#define SYS_MUNMAP 91
#define SYS_MMAP2  192

#define O_RDONLY   0
#define PROT_READ  1
#define MAP_SHARED 1
#define MAP_LEN    0x1000u
#define LWH2F_BASE 0xff200000u

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

static long syscall6(long n, long a0, long a1, long a2,
                     long a3, long a4, long a5) {
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

static usize str_len(const char *s) {
  usize n = 0;
  while (s[n]) ++n;
  return n;
}

static void write_text(int fd, const char *s) {
  usize len = str_len(s);
  while (len) {
    long n = syscall3(SYS_WRITE, fd, (long)s, (long)len);
    if (n <= 0) return;
    s += n;
    len -= (usize)n;
  }
}

static void write_hex(const char *name, u32 value) {
  static const char hex[] = "0123456789abcdef";
  char buf[40];
  int i = 0;
  while (name[i]) { buf[i] = name[i]; ++i; }
  buf[i++] = ' '; buf[i++] = '='; buf[i++] = ' ';
  buf[i++] = '0'; buf[i++] = 'x';
  for (int shift = 28; shift >= 0; shift -= 4)
    buf[i++] = hex[(value >> shift) & 0xfu];
  buf[i++] = '\n'; buf[i] = 0;
  write_text(1, buf);
}

static int run(void) {
  int fd = (int)syscall3(SYS_OPEN, (long)"/dev/mem", O_RDONLY, 0);
  if (fd < 0) { write_text(2, "open /dev/mem failed\n"); return 1; }

  long mapped = syscall6(SYS_MMAP2, 0, MAP_LEN, PROT_READ, MAP_SHARED,
                         fd, LWH2F_BASE >> 12);
  if ((usize)mapped >= (usize)-4095) {
    write_text(2, "mmap2 failed\n");
    syscall1(SYS_CLOSE, fd);
    return 1;
  }

  volatile const u32 *regs = (volatile const u32 *)mapped;
  u32 id = regs[0], control = regs[1], status = regs[2], cluster_base = regs[3];
  write_hex("ID          ", id);
  write_hex("CONTROL     ", control);
  write_hex("STATUS      ", status);
  write_hex("CLUSTER_BASE", cluster_base);
  syscall3(SYS_MUNMAP, mapped, MAP_LEN, 0);
  syscall1(SYS_CLOSE, fd);

  if (id != 0x48300005u || control != 0 || (status & 3u) != 1u ||
      cluster_base != 0x2000u) {
    write_text(2, "FAIL: unexpected H0.5 reset-held identity state\n");
    return 2;
  }
  write_text(1, "H0.5_READ_ONLY_PASS\n");
  return 0;
}

void _start(void) {
  syscall1(SYS_EXIT, run());
  syscall0(SYS_EXIT);
}
