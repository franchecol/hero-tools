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

#include <ctype.h>
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

#define SCTL_SCRATCH_0_REG_OFFSET 0x14U
#define SCTL_SCRATCH_1_REG_OFFSET 0x18U
#define SCTL_SCRATCH_2_REG_OFFSET 0x1cU

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
static unsigned fake_launch_sequence;
static int fake_bridge_failed;

static int fake_enabled(void) {
    const char *env = getenv("OCCAMY_FAKE_DRIVER");
    return env && strcmp(env, "0") != 0;
}

static int fake_complete_enabled(void) {
    const char *env = getenv("OCCAMY_FAKE_DEVICE_COMPLETE");
    return fake_enabled() && env && strcmp(env, "0") != 0;
}

static const char *fake_capture_path(void) {
    const char *env = getenv("OCCAMY_FAKE_CAPTURE_LAUNCH");
    return (fake_enabled() && env && env[0] != '\0') ? env : NULL;
}

static int fake_capture_enabled(void) { return fake_capture_path() != NULL; }

static const char *fake_capture_dir(void) {
    const char *env = getenv("OCCAMY_FAKE_CAPTURE_DIR");
    return (fake_enabled() && env && env[0] != '\0') ? env : NULL;
}

static const char *fake_bridge_dir(void) {
    const char *env = getenv("OCCAMY_FAKE_BRIDGE_DIR");
    return (fake_enabled() && env && env[0] != '\0') ? env : NULL;
}

static unsigned fake_bridge_max_launches(void) {
    const char *env = getenv("OCCAMY_FAKE_BRIDGE_MAX_LAUNCHES");
    char *end = NULL;
    unsigned long value;

    if (!env || env[0] == '\0') {
        return 0;
    }

    value = strtoul(env, &end, 0);
    if (end == env) {
        return 0;
    }
    return (unsigned)value;
}

static unsigned fake_bridge_timeout_seconds(void) {
    const char *env = getenv("OCCAMY_FAKE_BRIDGE_TIMEOUT_SECONDS");
    char *end = NULL;
    unsigned long value;

    if (!env || env[0] == '\0') {
        return 900;
    }

    value = strtoul(env, &end, 0);
    if (end == env || value == 0) {
        return 900;
    }
    return (unsigned)value;
}

static int fake_bridge_should_replay(unsigned sequence) {
    unsigned max_launches = fake_bridge_max_launches();

    if (!fake_bridge_dir()) {
        return 0;
    }
    return max_launches == 0 || sequence <= max_launches;
}

static size_t fake_capture_bytes(void) {
    const char *env = getenv("OCCAMY_FAKE_CAPTURE_BYTES");
    char *end = NULL;
    unsigned long value;

    if (!env || env[0] == '\0') {
        return 128;
    }

    value = strtoul(env, &end, 0);
    if (end == env || value == 0) {
        return 128;
    }
    if (value > 4096) {
        return 4096;
    }
    return (size_t)value;
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

static const char *region_name(const struct fake_region *region) {
    switch (region->mmap_id) {
    case SOC_CTRL_MMAP_ID:
        return "soc_ctrl";
    case DMA_BUFS_MMAP_ID:
        return "dma_bufs";
    case L3_MMAP_ID:
        return "l3";
    case QUADRANT_CTRL_MMAP_ID:
        return "quadrant_ctrl";
    case CLINT_MMAP_ID:
        return "clint";
    case SCRATCHPAD_WIDE_MMAP_ID:
        return "scratchpad_wide";
    case SNITCH_CLUSTER_MMAP_ID:
        return "snitch_cluster";
    default:
        return "unknown";
    }
}

static struct fake_region *lookup_region_by_paddr(uint64_t paddr) {
    for (size_t i = 0; i < sizeof(regions) / sizeof(regions[0]); ++i) {
        struct fake_region *region = &regions[i];
        if (!region->mapping || paddr < region->pbase) {
            continue;
        }
        if ((paddr - region->pbase) < region->size) {
            return region;
        }
    }
    return NULL;
}

static size_t mapped_bytes_available(uint64_t paddr) {
    struct fake_region *region = lookup_region_by_paddr(paddr);
    if (!region) {
        return 0;
    }
    return region->size - (size_t)(paddr - region->pbase);
}

static void *mapped_ptr_from_paddr(uint64_t paddr, size_t size) {
    struct fake_region *region = lookup_region_by_paddr(paddr);
    size_t offset;

    if (!region) {
        return NULL;
    }

    offset = (size_t)(paddr - region->pbase);
    if (size > region->size - offset) {
        return NULL;
    }
    return (uint8_t *)region->mapping + offset;
}

static uint32_t read_mapped_u32(uint64_t paddr, int *ok) {
    uint32_t value = 0;
    void *ptr = mapped_ptr_from_paddr(paddr, sizeof(value));

    if (!ptr) {
        *ok = 0;
        return 0;
    }

    memcpy(&value, ptr, sizeof(value));
    *ok = 1;
    return value;
}

static int write_mapped_u32(uint64_t paddr, uint32_t value) {
    void *ptr = mapped_ptr_from_paddr(paddr, sizeof(value));

    if (!ptr) {
        fprintf(stderr,
                "[occamy-fake-driver] bridge W32 address 0x%llx is not mapped\n",
                (unsigned long long)paddr);
        return -1;
    }

    memcpy(ptr, &value, sizeof(value));
    fprintf(stderr,
            "[occamy-fake-driver] applied bridge W32 0x%08x -> 0x%llx\n",
            value, (unsigned long long)paddr);
    return 0;
}

static int apply_bridge_response_command(const char *line, unsigned sequence) {
    char op[16];
    unsigned long long paddr = 0;
    unsigned long long value = 0;
    const unsigned char *cursor = (const unsigned char *)line;
    int fields;

    while (*cursor && isspace(*cursor)) {
        ++cursor;
    }
    if (*cursor == '\0' || *cursor == '#') {
        return 0;
    }

    fields = sscanf((const char *)cursor, "%15s %llx %llx", op, &paddr, &value);
    if (fields == EOF || fields == 0) {
        return 0;
    }
    if (strcmp(op, "W32") == 0 && fields == 3 && value <= UINT32_MAX) {
        return write_mapped_u32((uint64_t)paddr, (uint32_t)value);
    }

    fprintf(stderr,
            "[occamy-fake-driver] invalid bridge response command for sequence #%u: %s",
            sequence, line);
    return -1;
}

static void json_region(FILE *f, const char *name, uint64_t paddr) {
    struct fake_region *region = lookup_region_by_paddr(paddr);

    fprintf(f, ",\"%s\":", name);
    if (!region) {
        fprintf(f, "null");
        return;
    }

    fprintf(f,
            "{\"mmap_id\":%d,\"pbase\":\"0x%08llx\",\"offset\":\"0x%zx\"}",
            region->mmap_id, (unsigned long long)region->pbase,
            (size_t)(paddr - region->pbase));
}

static void json_word_array(FILE *f, const char *name, uint64_t paddr, size_t bytes) {
    size_t available = mapped_bytes_available(paddr);
    size_t n_words;

    fprintf(f, ",\"%s\":[", name);
    if (available == 0) {
        fprintf(f, "]");
        return;
    }

    if (bytes > available) {
        bytes = available;
    }
    n_words = bytes / sizeof(uint32_t);

    for (size_t i = 0; i < n_words; ++i) {
        int ok = 0;
        uint32_t word = read_mapped_u32(paddr + i * sizeof(uint32_t), &ok);
        if (i != 0) {
            fprintf(f, ",");
        }
        if (ok) {
            fprintf(f, "\"0x%08x\"", word);
        } else {
            fprintf(f, "null");
        }
    }
    fprintf(f, "]");
}

static size_t align_up_size(size_t value, size_t align) {
    return (value + align - 1) & ~(align - 1);
}

static size_t region_used_size(const struct fake_region *region) {
    const uint8_t *data = (const uint8_t *)region->mapping;
    size_t used = region->size;

    if (!data) {
        return 0;
    }

    while (used > 0 && data[used - 1] == 0) {
        --used;
    }

    if (used == 0) {
        return 0;
    }

    used = align_up_size(used, 4096);
    return used > region->size ? region->size : used;
}

static int write_region_dump(const char *path, const void *data, size_t size) {
    FILE *f = fopen(path, "wb");

    if (!f) {
        return -1;
    }
    if (size && fwrite(data, 1, size, f) != size) {
        fclose(f);
        return -1;
    }
    return fclose(f);
}

static void dump_launch_snapshot(unsigned sequence) {
    const char *dir = fake_capture_dir();
    char manifest_path[4096];
    FILE *manifest;

    if (!dir) {
        return;
    }

    snprintf(manifest_path, sizeof(manifest_path), "%s/snapshots.jsonl", dir);
    manifest = fopen(manifest_path, "a");
    if (!manifest) {
        fprintf(stderr, "[occamy-fake-driver] failed to open snapshot manifest %s: %s\n",
                manifest_path, strerror(errno));
        return;
    }

    fprintf(manifest, "{\"sequence\":%u,\"regions\":[", sequence);
    int emitted = 0;
    for (size_t i = 0; i < sizeof(regions) / sizeof(regions[0]); ++i) {
        struct fake_region *region = &regions[i];
        const char *name = region_name(region);
        char file_name[128];
        char file_path[4096];
        size_t used = region_used_size(region);

        if (!region->mapping || used == 0) {
            continue;
        }

        snprintf(file_name, sizeof(file_name), "launch-%04u-%s.bin", sequence, name);
        snprintf(file_path, sizeof(file_path), "%s/%s", dir, file_name);

        if (write_region_dump(file_path, region->mapping, used) != 0) {
            fprintf(stderr, "[occamy-fake-driver] failed to write snapshot %s: %s\n",
                    file_path, strerror(errno));
            continue;
        }

        if (emitted) {
            fprintf(manifest, ",");
        }
        fprintf(manifest,
                "{\"name\":\"%s\",\"mmap_id\":%d,\"pbase\":\"0x%08llx\","
                "\"dump_size\":\"0x%zx\",\"file\":\"%s\"}",
                name, region->mmap_id, (unsigned long long)region->pbase, used,
                file_name);
        emitted = 1;
    }
    fprintf(manifest, "]}\n");
    fclose(manifest);

    fprintf(stderr, "[occamy-fake-driver] captured snapshot #%u to %s\n",
            sequence, dir);
}

static unsigned capture_launch_packet(void) {
    const char *path = fake_capture_path();
    size_t bytes = fake_capture_bytes();
    uint64_t target_fn = fake_launch_words[1];
    uint64_t arg_ptr = fake_launch_words[2];
    uint64_t soc_scratch_base = 0x02000000ULL;
    int ok0 = 0;
    int ok1 = 0;
    int ok2 = 0;
    uint32_t scratch0 = read_mapped_u32(soc_scratch_base + SCTL_SCRATCH_0_REG_OFFSET, &ok0);
    uint32_t scratch1 = read_mapped_u32(soc_scratch_base + SCTL_SCRATCH_1_REG_OFFSET, &ok1);
    uint32_t scratch2 = read_mapped_u32(soc_scratch_base + SCTL_SCRATCH_2_REG_OFFSET, &ok2);
    FILE *f;

    if (!path) {
        return 0;
    }

    f = fopen(path, "a");
    if (!f) {
        fprintf(stderr, "[occamy-fake-driver] failed to open capture path %s: %s\n",
                path, strerror(errno));
        return 0;
    }

    unsigned sequence = ++fake_launch_sequence;

    fprintf(f,
            "{\"sequence\":%u,\"start\":\"0x%08x\",\"target_fn\":\"0x%08x\","
            "\"arg_ptr\":\"0x%08x\",\"workers\":%u",
            sequence, fake_launch_words[0], fake_launch_words[1],
            fake_launch_words[2], fake_launch_words[3]);
    json_region(f, "target_region", target_fn);
    json_region(f, "arg_region", arg_ptr);
    json_region(f, "mailbox_layout_region", scratch2);
    fprintf(f, ",\"soc_scratch\":{");
    fprintf(f, "\"s0\":");
    ok0 ? fprintf(f, "\"0x%08x\"", scratch0) : fprintf(f, "null");
    fprintf(f, ",\"s1\":");
    ok1 ? fprintf(f, "\"0x%08x\"", scratch1) : fprintf(f, "null");
    fprintf(f, ",\"s2\":");
    ok2 ? fprintf(f, "\"0x%08x\"", scratch2) : fprintf(f, "null");
    fprintf(f, "}");
    json_word_array(f, "mailbox_layout_words", scratch2, 16);
    json_word_array(f, "arg_words", arg_ptr, bytes);
    json_word_array(f, "target_words", target_fn, bytes < 64 ? bytes : 64);
    fprintf(f, "}\n");
    fclose(f);

    fprintf(stderr, "[occamy-fake-driver] captured launch #%u to %s\n",
            sequence, path);
    dump_launch_snapshot(sequence);
    return sequence;
}

static int bridge_wait_for_replay(unsigned sequence) {
    const char *dir = fake_bridge_dir();
    char request_tmp[4096];
    char request_path[4096];
    char response_path[4096];
    char line[256];
    unsigned timeout_s = fake_bridge_timeout_seconds();
    unsigned polls = timeout_s * 10;
    int status = 1;
    FILE *f;

    if (!dir) {
        return 0;
    }

    snprintf(request_tmp, sizeof(request_tmp), "%s/requests/request-%04u.tmp.%ld",
             dir, sequence, (long)getpid());
    snprintf(request_path, sizeof(request_path), "%s/requests/request-%04u.json",
             dir, sequence);
    snprintf(response_path, sizeof(response_path), "%s/responses/response-%04u.status",
             dir, sequence);

    f = fopen(request_tmp, "w");
    if (!f) {
        fprintf(stderr, "[occamy-fake-driver] failed to write bridge request %s: %s\n",
                request_tmp, strerror(errno));
        return -1;
    }
    fprintf(f,
            "{\"sequence\":%u,\"target_fn\":\"0x%08x\","
            "\"arg_ptr\":\"0x%08x\",\"workers\":%u}\n",
            sequence, fake_launch_words[1], fake_launch_words[2],
            fake_launch_words[3]);
    if (fclose(f) != 0) {
        fprintf(stderr, "[occamy-fake-driver] failed to close bridge request %s: %s\n",
                request_tmp, strerror(errno));
        return -1;
    }
    if (rename(request_tmp, request_path) != 0) {
        fprintf(stderr, "[occamy-fake-driver] failed to publish bridge request %s: %s\n",
                request_path, strerror(errno));
        unlink(request_tmp);
        return -1;
    }

    fprintf(stderr, "[occamy-fake-driver] waiting for replay bridge sequence #%u\n",
            sequence);

    while (polls-- > 0) {
        if (access(response_path, R_OK) == 0) {
            break;
        }
        usleep(100000);
    }

    if (access(response_path, R_OK) != 0) {
        fprintf(stderr, "[occamy-fake-driver] replay bridge timed out for sequence #%u\n",
                sequence);
        return -1;
    }

    f = fopen(response_path, "r");
    if (!f) {
        fprintf(stderr, "[occamy-fake-driver] failed to open bridge response %s: %s\n",
                response_path, strerror(errno));
        return -1;
    }
    if (!fgets(line, sizeof(line), f) || sscanf(line, "%d", &status) != 1) {
        status = 1;
    }
    if (status == 0) {
        while (fgets(line, sizeof(line), f)) {
            if (apply_bridge_response_command(line, sequence) != 0) {
                status = 1;
                break;
            }
        }
    }
    fclose(f);

    if (status != 0) {
        fprintf(stderr, "[occamy-fake-driver] replay bridge failed for sequence #%u\n",
                sequence);
        return -1;
    }

    fprintf(stderr, "[occamy-fake-driver] replay bridge completed sequence #%u\n",
            sequence);
    return 0;
}

static void observe_mbox_write(uint32_t word, int complete_launch) {
    if (fake_launch_count == 0) {
        if (word == MBOX_DEVICE_START) {
            fake_launch_words[fake_launch_count++] = word;
        } else if (word == MBOX_DEVICE_STOP) {
            fprintf(stderr, "[occamy-fake-driver] observed MBOX_DEVICE_STOP\n");
        }
        return;
    }

    fake_launch_words[fake_launch_count++] = word;
    if (fake_launch_count == 4) {
        unsigned sequence;

        fprintf(stderr,
                "[occamy-fake-driver] target launch fn=0x%08x args=0x%08x workers=%u\n",
                fake_launch_words[1], fake_launch_words[2], fake_launch_words[3]);
        sequence = capture_launch_packet();
        if (complete_launch) {
            if (sequence != 0 && fake_bridge_should_replay(sequence) &&
                bridge_wait_for_replay(sequence) != 0) {
                fake_bridge_failed = 1;
            } else {
                fake_queue_put(MBOX_DEVICE_DONE);
                fake_queue_put(1);
            }
        }
        fake_launch_count = 0;
    }
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
    int complete_launch = fake_complete_enabled();
    int capture_launch = fake_capture_enabled();

    if (!complete_launch && !capture_launch) {
        if (!real_hero_dev_mbox_write) {
            real_hero_dev_mbox_write = must_sym("hero_dev_mbox_write");
        }
        return real_hero_dev_mbox_write(dev, word);
    }

    fprintf(stderr, "[occamy-fake-driver] mbox_write 0x%08x\n", word);
    observe_mbox_write(word, complete_launch);
    if (fake_bridge_failed) {
        return -1;
    }

    if (!complete_launch) {
        if (!real_hero_dev_mbox_write) {
            real_hero_dev_mbox_write = must_sym("hero_dev_mbox_write");
        }
        return real_hero_dev_mbox_write(dev, word);
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
