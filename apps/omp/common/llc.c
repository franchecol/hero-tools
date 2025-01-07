// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

#include <ctype.h>
#include <fcntl.h>
#include <math.h>
#include <omp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "llc.h"

uint64_t llc_devmap() {

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd == -1){
        printf("can not access /dev/mem\n" );
        return -1;
    }

    uint8_t *mmap_llc = (uint8_t*) mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0x3001000);
    uint64_t llc_base_virt = (uint64_t) mmap_llc;

    close(fd);

    return llc_base_virt;
}

void llc_enable(uint64_t llc_base_virt) {
    *((uint32_t *)(llc_base_virt + 0x0)) = 0x0;
    *((uint32_t *)(llc_base_virt + 0x4)) = 0x0;
    asm volatile("fence" ::: "memory");
    *((uint32_t *)(llc_base_virt + 0x10)) = 0x1;
}

void llc_flush(uint64_t llc_base_virt) {
    *((uint32_t *)(llc_base_virt + 0x8)) = 0xffffffff;
    *((uint32_t *)(llc_base_virt + 0xc)) = 0xffffffff;
    asm volatile("fence" ::: "memory");
    *((uint32_t *)(llc_base_virt + 0x10)) = 0x1;
}
