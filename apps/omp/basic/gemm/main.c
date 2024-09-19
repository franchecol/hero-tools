// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

////// HERO_1 includes /////
#ifdef __HERO_1
extern int* hero_device_cycles;
extern int hero_num_device_cycles;
////// HOST includes /////
#else
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

#include <libhero/hero_api.h>

static inline void fence()
{
    asm volatile("fence" ::: "memory");
}

#endif
///// ALL includes /////
#include "hero_64.h"
#include "gemm.h"
///// END includes /////

void kernel_1()
{
#pragma omp target device(1)
    asm volatile("nop");
}

void printvec(const char *name, DTYPE *v, int n) {
    printf("Vector %s: [ ", name);
    for(int i = 0; i < n; ++i)
        printf("%f, ", v[i]);
    printf("]\n");
}

void printrow(DTYPE *v, int n) {
    printf("[ ");
    for(int i = 0; i < n; ++i)
        printf("%f, ", v[i]);
    printf("]\n");
}

void printmat(DTYPE *v, int m, int n) {
    printf("[\n");
    for(int i = 0; i < m; ++i){
        printrow(&v[i*n], n);
    }
    printf("]\n");
}

#define IOMMU_BASE           0x2000a000
#define IOMMU_EVNT_OFFSET_L  0x00000160
#define IOMMU_EVNT_OFFSET_H  0x00000164
#define IOMMU_CNTR_OFFSET_L  0x00000068
#define IOMMU_CNTR_OFFSET_H  0x0000006c
#define IOMMU_DUMP_OFFSET_L  0x00000400
#define IOMMU_DUMP_OFFSET_H  0x00000404
#define IOMMU_INDX_OFFSET    0x00000800

/*
 * Gemm    : alpha*A*B + beta*C
 * A       : Input matrix A ([m][n])
 * B       : Input matrix B ([n][p])
 * C       : Input matrix C ([m][p])
 * alpha   : Input scalar alpha
 * beta    : Input scalar beta
 * out     : Output matrix  ([m][p])
*/

#define ALIGN_UP(size, align) ((size%align==0) ? size : size + align - (size%align))

int main(int argc, char *argv[])
{
    // Physical addresses
    uintptr_t A_phys, B_phys, C_phys, out_phys;
    // Virtual addresses
    DTYPE *A_virt = NULL, *B_virt = NULL, *C_virt = NULL, *out_virt = NULL;
    // Verification matrices / vectors
    DTYPE *A_test = NULL, *B_test = NULL, *C_test = NULL, *out_test = NULL;
    // Device virtual addresses
    DTYPE *A_iommu = NULL, *B_iommu = NULL, *C_iommu = NULL, *out_iommu = NULL;
    // Do / Don't map IOMMU flag
    int do_map = 0;
    // Return
    int ret;
    // sprintf buffer
    char toprint[128];

    int m       = 16;
    int n       = 16;
    int p       = 16;
    DTYPE alpha = 1.0f;
    DTYPE beta  = 1.0f;

    if (argc > 1)
        m = strtol(argv[1], NULL, 10);
    if (argc > 2)
        n = strtol(argv[2], NULL, 10);
    if (argc > 3)
        p = strtol(argv[3], NULL, 10);
    if (argc > 4)
        alpha = atof(argv[4]);
    if (argc > 5)
        beta = atof(argv[5]);
    if (argc > 6)
        do_map = strtol(argv[6], NULL, 10);

#ifndef __HERO_DEV
    // Mmap counters
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd == -1){
        printf("can not access /dev/mem\n" );
        return -1;
    }

    uint8_t *mmap_iommu = (uint8_t*) mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, IOMMU_BASE);
    uint64_t iommu_base_virt = (uint64_t) mmap_iommu;

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

#endif

    // Verification matrices
    A_test   = aligned_alloc(0x1000, ALIGN_UP(m * n *     sizeof(DTYPE), 0x1000));
    B_test   = aligned_alloc(0x1000, ALIGN_UP(    n * p * sizeof(DTYPE), 0x1000));
    C_test   = aligned_alloc(0x1000, ALIGN_UP(m *     p * sizeof(DTYPE), 0x1000));
    out_test = aligned_alloc(0x1000, ALIGN_UP(m *     p * sizeof(DTYPE), 0x1000));

    // Init Hero OpenMP runtime
    hero_add_timestamp("enter_init_omp", __func__, 0);
    kernel_1();

    // Prepare data in Linux's virtual memory region
    hero_add_timestamp("enter_prepare_data", __func__, 0);

    for (int i = 0; i < m; ++i) {
        for (int j = 0; j < n; ++j) {
            A_test[i * n + j] = i * n + j;
        }
    }

    for (int j = 0; j < n; ++j) {
        for (int k = 0; k < p; ++k) {
            B_test[j * p + k] = j * p + k;
        }
    }

    for (int i = 0; i < m; ++i) {
        for (int k = 0; k < p; ++k) {
            C_test[i * p + k] = i * p + k;
        }
    }

    // Allocate data in upper phisical memory region
    hero_add_timestamp("enter_alloc_data", __func__, 0);
    A_virt   = hero_dev_l3_malloc(NULL, m * n     * sizeof(DTYPE),   &A_phys);
    B_virt   = hero_dev_l3_malloc(NULL,     n * p * sizeof(DTYPE),   &B_phys);
    C_virt   = hero_dev_l3_malloc(NULL, m     * p * sizeof(DTYPE),   &C_phys);
    out_virt = hero_dev_l3_malloc(NULL, m     * p * sizeof(DTYPE), &out_phys);

    // Copy data to physical memory region
    hero_add_timestamp("enter_copy_data", __func__, 0);
    memcpy(A_virt, A_test, m * n     * sizeof(DTYPE));
    memcpy(B_virt, B_test,     n * p * sizeof(DTYPE));
    memcpy(C_virt, C_test, m     * p * sizeof(DTYPE));

    // Map allocated data into device IOMMU
    hero_add_timestamp("enter_map_data", __func__, 0);
    if (do_map) {
        A_iommu = (DTYPE *)hero_iommu_map_virt(NULL, m * n     * sizeof(DTYPE), A_test);
        B_iommu = (DTYPE *)hero_iommu_map_virt(NULL,     n * p * sizeof(DTYPE), B_test);
        C_iommu = (DTYPE *)hero_iommu_map_virt(NULL, m *     p * sizeof(DTYPE), C_test);
    }

    asm volatile("fence");

    // Offload
    snprintf(toprint, 128, "enter_omp_gemm-%u-%u-%u", m, n, p);
    hero_add_timestamp(toprint, __func__, 0);
    ret = gemm(out_phys, A_phys, B_phys, C_phys, m, n, p, alpha, beta);

    // Execution on host
    hero_add_timestamp("enter_verif", __func__, 0);
    for (int i = 0; i < m; ++i) {
        for (int k = 0; k < p; ++k) {
            DTYPE res = 0;
            for (int j = 0; j < n; ++j) {
                // res += A_test[i * n + j] * B_test[j * p + k];
                res += A_test[i * n + j] * B_test[k * n + j];
            }
            res *= alpha;
            res += beta * C_test[i * p + k];
            out_test[i * p + k] = res;
        }
    }
    hero_add_timestamp("end_verif", __func__, 0);

    asm volatile("fence");

    // Verify result
    for (int i = 0; i < m * p; i++) {
        if (out_test[i] != out_virt[i])
            printf("nope %i (%f != %f)\n", i, out_test[i], out_virt[i]);
    }

#ifndef __HERO_DEV

    uint32_t tlb_misses = *((uint32_t *) (iommu_base_virt + IOMMU_CNTR_OFFSET_L + 1 * 8));
    printf("TLB misses : %u\n", tlb_misses);

    uint32_t n_measurements = *((uint32_t *) (iommu_base_virt + IOMMU_INDX_OFFSET));
    printf("Num times  : %u\n", n_measurements - 1);


    uint32_t start_idx = 0;
    uint32_t n_iterations = n_measurements - 1;
    if (tlb_misses >= 128) {
        start_idx = (n_measurements % 128);
        n_iterations = 127;
    }

    printf("PTW cycles : ");
    uint32_t ptw_cycles, ptw_cycles_prev;
    ptw_cycles_prev = *((uint32_t *) (iommu_base_virt + IOMMU_DUMP_OFFSET_L + start_idx * 8));
    for (int i = start_idx + 1; i < start_idx + 1 + n_iterations; ++i) {
        ptw_cycles = *((uint32_t *) (iommu_base_virt + IOMMU_DUMP_OFFSET_L + ((i % 128) * 8)));
        printf("%u, ", ptw_cycles - ptw_cycles_prev);
        ptw_cycles_prev = ptw_cycles;
    }
    printf("\n");

#endif

    // Print all the recorded timestamps
    hero_print_timestamp();

    // Print the device cycles per region
    // for (int i = 0; i < hero_num_device_cycles; i++)
    //     printf("%u - ", hero_device_cycles[i]);
    // printf("\n");

    hero_dev_l3_free(NULL,   A_virt,   A_phys);
    hero_dev_l3_free(NULL,   B_virt,   B_phys);
    hero_dev_l3_free(NULL,   C_virt,   C_phys);
    hero_dev_l3_free(NULL, out_virt, out_phys);
    free(  A_test);
    free(  B_test);
    free(  C_test);
    free(out_test);

    return 0;
}
