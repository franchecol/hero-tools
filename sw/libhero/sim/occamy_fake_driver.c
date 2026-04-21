// Copyright 2026
// SPDX-License-Identifier: Apache-2.0
//
// User-space Occamy driver shim for the local M3 OpenMP smoke path.
//
// This library is built for the RISC-V Linux host ABI and loaded with
// LD_PRELOAD under qemu-riscv64.  It implements only the small character-driver
// ABI surface that libhero uses: open("/dev/occamydev--1"), IOCTL_MEM_INFOS,
// IOCTL_DMA_ALLOC, mmap(), munmap(), and close().

#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define OCCAMY_FAKE_DEVICE "/dev/occamydev--1"

#define SOC_CTRL_MMAP_ID 0
#define DMA_BUFS_MMAP_ID 1
#define L3_MMAP_ID 2
#define QUADRANT_CTRL_MMAP_ID 3
#define CLINT_MMAP_ID 5
#define SCRATCHPAD_WIDE_MMAP_ID 10
#define SNITCH_CLUSTER_MMAP_ID 100

#define IOCTL_DMA_ALLOC 0
#define IOCTL_MEM_INFOS 1

#define MBOX_DEVICE_START 0x02U
#define MBOX_DEVICE_DONE 0x04U
#define MBOX_DEVICE_STOP 0x0FU

typedef struct HeroDev HeroDev;

struct driver_ioctl_arg {
    size_t size;
    uint64_t result_phys_addr;
    uint64_t result_virt_addr;
    int mmap_id;
};

struct fake_region {
    int mmap_id;
    uint64_t pbase;
    size_t size;
    void *mapping;
};

static struct fake_region regions[] = {
    {SOC_CTRL_MMAP_ID, 0x02000000ULL, 0x00001000, NULL},
    {DMA_BUFS_MMAP_ID, 0x90000000ULL, 0x00001000, NULL},
    {L3_MMAP_ID, 0xC0000000ULL, 0x01000000, NULL},
    {QUADRANT_CTRL_MMAP_ID, 0x0B000000ULL, 0x00004000, NULL},
    {CLINT_MMAP_ID, 0x04000000ULL, 0x00100000, NULL},
    {SCRATCHPAD_WIDE_MMAP_ID, 0x71000000ULL, 0x00200000, NULL},
    {SNITCH_CLUSTER_MMAP_ID, 0x10000000ULL, 0x00020000, NULL},
};

static int fake_fd = -1;
static uint32_t fake_a2h_queue[64];
static unsigned fake_a2h_head;
static unsigned fake_a2h_tail;
static uint32_t fake_launch_words[4];
static unsigned fake_launch_count;

static int fake_enabled(void) {
    const char *env = getenv("OCCAMY_FAKE_DRIVER");
    return env && strcmp(env, "0") != 0;
}

static int fake_complete_enabled(void) {
    const char *env = getenv("OCCAMY_FAKE_DEVICE_COMPLETE");
    return fake_enabled() && env && strcmp(env, "0") != 0;
}

static int fake_queue_empty(void) { return fake_a2h_tail == fake_a2h_head; }

static int fake_queue_put(uint32_t word) {
    unsigned next = (fake_a2h_head + 1) % (sizeof(fake_a2h_queue) / sizeof(fake_a2h_queue[0]));
    if (next == fake_a2h_tail) {
        return -1;
    }
    fake_a2h_queue[fake_a2h_head] = word;
    fake_a2h_head = next;
    return 0;
}

static int fake_queue_get(uint32_t *word) {
    if (fake_queue_empty()) {
        return -1;
    }
    *word = fake_a2h_queue[fake_a2h_tail];
    fake_a2h_tail = (fake_a2h_tail + 1) % (sizeof(fake_a2h_queue) / sizeof(fake_a2h_queue[0]));
    return 0;
}

static void *must_sym(const char *name) {
    void *sym = dlsym(RTLD_NEXT, name);
    if (!sym) {
        fprintf(stderr, "[occamy-fake-driver] missing RTLD_NEXT symbol %s\n", name);
        abort();
    }
    return sym;
}

static struct fake_region *lookup_region(int mmap_id) {
    for (size_t i = 0; i < sizeof(regions) / sizeof(regions[0]); ++i) {
        if (regions[i].mmap_id == mmap_id) {
            return &regions[i];
        }
    }
    return NULL;
}

static void *map_region(struct fake_region *region, size_t requested_size) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    size_t size = requested_size > region->size ? requested_size : region->size;

    if (!real_mmap) {
        real_mmap = must_sym("mmap");
    }

    if (region->mapping) {
        return region->mapping;
    }

    region->mapping = real_mmap(NULL, size, PROT_READ | PROT_WRITE,
                                MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (region->mapping == MAP_FAILED) {
        region->mapping = NULL;
        return MAP_FAILED;
    }

    memset(region->mapping, 0, size);
    region->size = size;

    fprintf(stderr,
            "[occamy-fake-driver] mmap id=%d pbase=0x%llx size=0x%zx -> %p\n",
            region->mmap_id, (unsigned long long)region->pbase, region->size,
            region->mapping);
    return region->mapping;
}

int open(const char *pathname, int flags, ...) {
    static int (*real_open)(const char *, int, ...);
    mode_t mode = 0;

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }

    if (!real_open) {
        real_open = must_sym("open");
    }

    if (fake_enabled() && strcmp(pathname, OCCAMY_FAKE_DEVICE) == 0) {
        if (fake_fd < 0) {
            fake_fd = real_open("/dev/zero", O_RDWR);
        }
        fprintf(stderr, "[occamy-fake-driver] open %s -> fd %d\n", pathname, fake_fd);
        return fake_fd;
    }

    if (flags & O_CREAT) {
        return real_open(pathname, flags, mode);
    }
    return real_open(pathname, flags);
}

int open64(const char *pathname, int flags, ...) {
    mode_t mode = 0;

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return open(pathname, flags, mode);
    }
    return open(pathname, flags);
}

int ioctl(int fd, unsigned long request, ...) {
    static int (*real_ioctl)(int, unsigned long, ...);
    va_list ap;
    struct driver_ioctl_arg *arg;

    va_start(ap, request);
    arg = va_arg(ap, struct driver_ioctl_arg *);
    va_end(ap);

    if (!real_ioctl) {
        real_ioctl = must_sym("ioctl");
    }

    if (!fake_enabled() || fd != fake_fd) {
        return real_ioctl(fd, request, arg);
    }

    if (!arg) {
        errno = EFAULT;
        return -1;
    }

    switch (request) {
    case IOCTL_MEM_INFOS: {
        struct fake_region *region = lookup_region(arg->mmap_id);
        if (!region) {
            errno = EINVAL;
            return -1;
        }
        arg->size = region->size;
        arg->result_phys_addr = region->pbase;
        arg->result_virt_addr = (uintptr_t)region->mapping;
        fprintf(stderr,
                "[occamy-fake-driver] ioctl MEM_INFOS id=%d pbase=0x%llx size=0x%zx\n",
                arg->mmap_id, (unsigned long long)arg->result_phys_addr, arg->size);
        return 0;
    }
    case IOCTL_DMA_ALLOC: {
        struct fake_region *region = lookup_region(DMA_BUFS_MMAP_ID);
        if (!region) {
            errno = EINVAL;
            return -1;
        }
        region->size = arg->size ? arg->size : region->size;
        arg->result_phys_addr = region->pbase;
        arg->result_virt_addr = (uintptr_t)region->mapping;
        fprintf(stderr,
                "[occamy-fake-driver] ioctl DMA_ALLOC pbase=0x%llx size=0x%zx\n",
                (unsigned long long)arg->result_phys_addr, arg->size);
        return 0;
    }
    default:
        errno = EINVAL;
        return -1;
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);

    if (!real_mmap) {
        real_mmap = must_sym("mmap");
    }

    if (fake_enabled() && fd == fake_fd) {
        long page_size = sysconf(_SC_PAGESIZE);
        int mmap_id = (int)(offset / page_size);
        struct fake_region *region = lookup_region(mmap_id);
        (void)addr;
        (void)prot;
        (void)flags;

        if (!region) {
            errno = EINVAL;
            return MAP_FAILED;
        }
        return map_region(region, length);
    }

    return real_mmap(addr, length, prot, flags, fd, offset);
}

int munmap(void *addr, size_t length) {
    static int (*real_munmap)(void *, size_t);

    if (!real_munmap) {
        real_munmap = must_sym("munmap");
    }

    if (fake_enabled()) {
        for (size_t i = 0; i < sizeof(regions) / sizeof(regions[0]); ++i) {
            if (regions[i].mapping == addr) {
                (void)length;
                return 0;
            }
        }
    }

    return real_munmap(addr, length);
}

int close(int fd) {
    static int (*real_close)(int);

    if (!real_close) {
        real_close = must_sym("close");
    }

    if (fake_enabled() && fd == fake_fd) {
        fake_fd = -1;
    }

    return real_close(fd);
}

int hero_dev_mbox_write(HeroDev *dev, uint32_t word) {
    static int (*real_hero_dev_mbox_write)(HeroDev *, uint32_t);
    (void)dev;

    if (!fake_complete_enabled()) {
        if (!real_hero_dev_mbox_write) {
            real_hero_dev_mbox_write = must_sym("hero_dev_mbox_write");
        }
        return real_hero_dev_mbox_write(dev, word);
    }

    fprintf(stderr, "[occamy-fake-driver] mbox_write 0x%08x\n", word);

    if (fake_launch_count == 0) {
        if (word == MBOX_DEVICE_START) {
            fake_launch_words[fake_launch_count++] = word;
        } else if (word == MBOX_DEVICE_STOP) {
            fprintf(stderr, "[occamy-fake-driver] observed MBOX_DEVICE_STOP\n");
        }
        return 0;
    }

    fake_launch_words[fake_launch_count++] = word;
    if (fake_launch_count == 4) {
        fprintf(stderr,
                "[occamy-fake-driver] fake target launch fn=0x%08x args=0x%08x workers=%u\n",
                fake_launch_words[1], fake_launch_words[2], fake_launch_words[3]);
        fake_queue_put(MBOX_DEVICE_DONE);
        fake_queue_put(1);
        fake_launch_count = 0;
    }

    return 0;
}

int hero_dev_mbox_read(const HeroDev *dev, uint32_t *buffer, size_t n_words) {
    static int (*real_hero_dev_mbox_read)(const HeroDev *, uint32_t *, size_t);
    (void)dev;

    if (!fake_complete_enabled()) {
        if (!real_hero_dev_mbox_read) {
            real_hero_dev_mbox_read = must_sym("hero_dev_mbox_read");
        }
        return real_hero_dev_mbox_read(dev, buffer, n_words);
    }

    while (n_words--) {
        uint32_t word = 0;
        if (fake_queue_get(&word)) {
            return -1;
        }
        buffer[n_words] = word;
        fprintf(stderr, "[occamy-fake-driver] mbox_read  0x%08x\n", word);
    }

    return 0;
}
