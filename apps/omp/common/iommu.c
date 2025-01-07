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

#include "iommu.h"

uint64_t iommu_devmap() {

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd == -1){
        printf("can not access /dev/mem\n" );
        return -1;
    }

    uint8_t *mmap_iommu = (uint8_t*) mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, IOMMU_BASE);
    uint64_t iommu_base_virt = (uint64_t) mmap_iommu;

    close(fd);

    return iommu_base_virt;
}

void iommu_enable(uint64_t iommu_base_virt) {
    uint64_t *ddtp_ptr = (uint64_t *) (iommu_base_virt + 0x10);
    uint64_t ddtp = *ddtp_ptr;
    *ddtp_ptr = (ddtp & 0xFFFFFFFFFFFFFFF0) | 0x4;
}

void iommu_disable(uint64_t iommu_base_virt) {
    uint64_t *ddtp_ptr = (uint64_t *) (iommu_base_virt + 0x10);
    uint64_t ddtp = *ddtp_ptr;
    *ddtp_ptr = (ddtp & 0xFFFFFFFFFFFFFFF0) | 0x1;
}

void iommu_reset_counters(uint64_t iommu_base_virt) {

    // Reset idx register to 0
    *((uint32_t *)(iommu_base_virt + IOMMU_INDX_OFFSET)) = 0;

    // Reset dumps to 0
    for (int i = 0; i < 128; ++i) {
        *((uint32_t *)(iommu_base_virt + IOMMU_DUMP_OFFSET_L + i * 8)) = 0;
        *((uint32_t *)(iommu_base_virt + IOMMU_DUMP_OFFSET_H + i * 8)) = 0;
    }

    // Reset counters to 0
    for (int i = 0; i < 8; ++i) {
        *((uint32_t *)(iommu_base_virt + IOMMU_CNTR_OFFSET_L + i * 8)) = 0;
        *((uint32_t *)(iommu_base_virt + IOMMU_CNTR_OFFSET_H + i * 8)) = 0;
    }

    // Set events appropriately (EVT_0 == s1_ptw, EVT_1 == tlb_miss)
    *((uint32_t *)(iommu_base_virt + IOMMU_EVNT_OFFSET_L + 0 * 8)) = 0x7;
    *((uint32_t *)(iommu_base_virt + IOMMU_EVNT_OFFSET_L + 1 * 8)) = 0x4;

}

void iommu_print_stats(uint64_t iommu_base_virt) {

    uint32_t tlb_misses = *((uint32_t *) (iommu_base_virt + IOMMU_CNTR_OFFSET_L + 1 * 8));
    printf("n_tlb_misses   : %u\n", tlb_misses);

    uint32_t ptw_tot = *((uint32_t *) (iommu_base_virt + IOMMU_CNTR_OFFSET_L + 0 * 8));
    printf("tot_ptw_time   : %u\n", ptw_tot);

    uint32_t n_measurements = *((uint32_t *) (iommu_base_virt + IOMMU_INDX_OFFSET));
    printf("n_measurements : %u\n", (n_measurements - 1) > 127 ? 127 : (n_measurements - 1));

    uint32_t start_idx = 0;
    uint32_t n_iterations = n_measurements - 1;
    if (tlb_misses >= 128) {
        start_idx = (n_measurements % 128);
        n_iterations = 127;
    }

    printf("ptw_times      : ");
    uint32_t ptw_cycles, ptw_cycles_prev;
    ptw_cycles_prev = *((uint32_t *) (iommu_base_virt + IOMMU_DUMP_OFFSET_L + start_idx * 8));
    for (int i = start_idx + 1; i < start_idx + 1 + n_iterations; ++i) {
        ptw_cycles = *((uint32_t *) (iommu_base_virt + IOMMU_DUMP_OFFSET_L + ((i % 128) * 8)));
        printf("%u, ", ptw_cycles - ptw_cycles_prev);
        ptw_cycles_prev = ptw_cycles;
    }
    printf("\n");

}
