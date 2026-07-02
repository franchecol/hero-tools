#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define D2_LWH2F_BASE 0xff200000u
#define D2_SPAN       0x1000u

#define REG_ID        0x00u
#define REG_CONTROL   0x04u
#define REG_STATUS    0x08u
#define REG_A         0x0cu
#define REG_B         0x10u
#define REG_OPCODE    0x14u
#define REG_RESULT    0x18u
#define REG_CYCLES    0x1cu

static uint32_t read_reg(volatile uint8_t *base, uint32_t offset) {
    return *(volatile uint32_t *)(base + offset);
}

static void write_reg(volatile uint8_t *base, uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(base + offset) = value;
}

int main(void) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        return 1;
    }

    volatile uint8_t *regs = mmap(NULL, D2_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, D2_LWH2F_BASE);
    if (regs == MAP_FAILED) {
        fprintf(stderr, "mmap failed: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    uint32_t id = read_reg(regs, REG_ID);
    printf("ID      = 0x%08x\n", id);
    if (id != 0x44320001u) {
        fprintf(stderr, "unexpected ID, check bridge base address and bitstream\n");
        munmap((void *)regs, D2_SPAN);
        close(fd);
        return 1;
    }

    write_reg(regs, REG_CONTROL, 0x2u);
    write_reg(regs, REG_A, 0x03u);
    write_reg(regs, REG_B, 0x05u);
    write_reg(regs, REG_OPCODE, 0x00u);
    write_reg(regs, REG_CONTROL, 0x01u);

    uint32_t status = 0;
    for (unsigned i = 0; i < 1000000; ++i) {
        status = read_reg(regs, REG_STATUS);
        if (status & 0x1u) {
            break;
        }
    }

    uint32_t result = read_reg(regs, REG_RESULT);
    uint32_t cycles = read_reg(regs, REG_CYCLES);

    printf("STATUS  = 0x%08x\n", status);
    printf("RESULT  = 0x%08x\n", result);
    printf("CYCLES  = 0x%08x\n", cycles);

    munmap((void *)regs, D2_SPAN);
    close(fd);

    return result == 0x08u ? 0 : 1;
}

