#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define LW_BRIDGE_BASE 0xff200000u
#define MAP_SIZE       0x1000u
#define EXPECTED_ID    0x48300005u

int main(void) {
  int fd = open("/dev/mem", O_RDONLY | O_SYNC);
  if (fd < 0) {
    fprintf(stderr, "open /dev/mem: %s\n", strerror(errno));
    return 1;
  }

  volatile const uint32_t *regs = mmap(NULL, MAP_SIZE, PROT_READ, MAP_SHARED,
                                       fd, LW_BRIDGE_BASE);
  if (regs == MAP_FAILED) {
    fprintf(stderr, "mmap: %s\n", strerror(errno));
    close(fd);
    return 1;
  }

  uint32_t id = regs[0];
  uint32_t control = regs[1];
  uint32_t status = regs[2];
  uint32_t cluster_base = regs[3];

  printf("ID           = 0x%08x\n", id);
  printf("CONTROL      = 0x%08x\n", control);
  printf("STATUS       = 0x%08x\n", status);
  printf("CLUSTER_BASE = 0x%08x\n", cluster_base);

  munmap((void *)regs, MAP_SIZE);
  close(fd);

  if (id != EXPECTED_ID || control != 0 || (status & 3u) != 1u ||
      cluster_base != 0x1000u) {
    fputs("FAIL: unexpected H0.5 reset-held identity state\n", stderr);
    return 2;
  }

  puts("H0.5_READ_ONLY_PASS");
  return 0;
}
