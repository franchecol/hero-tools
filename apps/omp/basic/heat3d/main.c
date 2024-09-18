// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig <cykoenig@iis.ee.ethz.ch>

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
#include "heat3d.h"
///// END includes /////

void kernel_1()
{
#pragma omp target device(1)
    asm volatile("nop");
}

void printrow(DTYPE *v, int n) {
    printf("    [ ");
    for(int i = 0; i < n; ++i)
        printf("%f, ", v[i]);
    printf("]\n");
}

void printmat(DTYPE *v, int m, int n) {
    printf("  [\n");
    for(int i = 0; i < m; ++i){
        printrow(&v[i*n], n);
    }
    printf("  ],\n");
}

void printmat3d(DTYPE *v, int m, int n, int p) {
    printf("[\n");
    for(int k = 0; k < p; ++k){
        printmat(&v[k*m*n], m, n);
    }
    printf("]\n");
}

/*
 * Heat 3D kernel
 * A          : Input 3D matrix A
 * B          : Auxiliary 3D matrix B
 * iterations : Number of timesteps
*/

#define MIN(A, B) (A <  B ? A : B)
#define MAX(A, B) (A >= B ? A : B)
#define ALIGN_UP(size, align) ((size%align==0) ? size : size + align - (size%align))

int main(int argc, char *argv[])
{
    // Physical addresses
    uintptr_t A_phys, B_phys;
    // Virtual addresses
    DTYPE *A_virt = NULL, *B_virt = NULL;
    // Verification matrices / vectors
    DTYPE *A_test = NULL, *B_test = NULL;
    // Device virtual addresses
    DTYPE *A_iommu = NULL, *B_iommu = NULL;
    // Do / Don't map IOMMU flag
    int do_map = 0;
    // Return
    int ret;
    // sprintf buffer
    char toprint[128];

    int height     = 16;
    int width      = 16;
    int depth      = 16;
    int iterations = 1;
    
    // Fixed to this value by algorithm
    const DTYPE alpha = 0.125f;

    if (argc > 1)
        height = strtol(argv[1], NULL, 10);
    if (argc > 2)
        width = strtol(argv[2], NULL, 10);
    if (argc > 3)
        depth = strtol(argv[3], NULL, 10);
    if (argc > 4)
        iterations = strtol(argv[4], NULL, 10);
    if (argc > 5)
        do_map = strtol(argv[5], NULL, 10);

    // Verification matrices
    A_test = aligned_alloc(0x1000, ALIGN_UP(width * height * depth * sizeof(DTYPE), 0x1000));
    B_test = aligned_alloc(0x1000, ALIGN_UP(width * height * depth * sizeof(DTYPE), 0x1000));

    // Init Hero OpenMP runtime
    hero_add_timestamp("enter_init_omp", __func__, 0);
    kernel_1();

    // Prepare data in Linux's virtual memory region
    hero_add_timestamp("enter_prepare_data", __func__, 0);
    for(int k = 0; k < depth; k++) {
        for(int i = 0; i < height; ++i) {
            for(int j = 0; j < width; ++j) {
                A_test[k * height * width + i * width + j] = (k * height * width + i * width + j) % 16;
                B_test[k * height * width + i * width + j] = 0;
            }
        }
    }

    // Allocate data in upper phisical memory region
    hero_add_timestamp("enter_alloc_data", __func__, 0);
    A_virt = hero_dev_l3_malloc(NULL, width * height * depth * sizeof(DTYPE), &A_phys);
    B_virt = hero_dev_l3_malloc(NULL, width * height * depth * sizeof(DTYPE), &B_phys);

    // Copy data to physical memory region
    hero_add_timestamp("enter_copy_data", __func__, 0);
    memcpy(A_virt, A_test, height * width * depth * sizeof(DTYPE));
    memcpy(B_virt, B_test, height * width * depth * sizeof(DTYPE));

    // Map allocated data into device IOMMU
    hero_add_timestamp("enter_map_data", __func__, 0);
    if (do_map) {
        A_iommu = (DTYPE *)hero_iommu_map_virt(NULL, height * width * depth * sizeof(DTYPE), A_test);
        B_iommu = (DTYPE *)hero_iommu_map_virt(NULL, height * width * depth * sizeof(DTYPE), B_test);
    }

    asm volatile("fence");

    // Offload
    snprintf(toprint, 128, "enter_omp_heat3d-%u-%u-%u", height, width, depth);
    hero_add_timestamp(toprint, __func__, 0);
    ret = heat3d(A_phys, B_phys, height, width, depth, alpha, iterations);

    DTYPE *sn_out = (iterations % 2 == 0) ? A_virt : B_virt;

    // Execution on host
    hero_add_timestamp("enter_verif", __func__, 0);
    DTYPE *buf_in, *buf_out;
    
    for(int t = 0; t < iterations; ++t) {
        
        if(t % 2 == 0) {
            buf_in  = A_test;
            buf_out = B_test;
        } else {
            buf_in  = B_test;
            buf_out = A_test;
        }
    
        for(int k = 0; k < depth; k++) {
            for(int i = 0; i < height; ++i) {
                for(int j = 0; j < width; ++j) {
                    DTYPE prev = buf_in[k * height * width + i * width + j];
                    DTYPE delta = 0;
                    
                    if(j > 0) {
                        delta += (buf_in[k * height * width + i * width + j - 1] - prev);
                    } else {
                        delta += (0 - prev);
                    }
                    if(j < width - 1) {
                        delta += (buf_in[k * height * width + i * width + j + 1] - prev);
                    } else {
                        delta += (0 - prev);
                    }

                    if(i > 0) {
                        delta += (buf_in[k * height * width + (i-1) * width + j] - prev);
                    } else {
                        delta += (0 - prev);
                    }
                    if(i < height - 1) {
                        delta += (buf_in[k * height * width + (i+1) * width + j] - prev);
                    } else {
                        delta += (0 - prev);
                    }

                    if(k > 0) {
                        delta += (buf_in[(k-1) * height * width + i * width + j] - prev);
                    } else {
                        delta += (0 - prev);
                    }
                    if(k < depth - 1) {
                        delta += (buf_in[(k+1) * height * width + i * width + j] - prev);
                    } else {
                        delta += (0 - prev);
                    }

                    buf_out[k * height * width + i * width + j] = prev + alpha * delta;
                }
            }
        }
    }
    hero_add_timestamp("end_verif", __func__, 0);

    asm volatile("fence");

    DTYPE eps = 0.001f;
    // Verify result
    for (int i = 0; i < depth * height * width; i++) {
        if (MAX(buf_out[i], sn_out[i]) - MIN(buf_out[i], sn_out[i]) > eps)
            printf("nope %i (%f != %f)\n\r", i, buf_out[i], sn_out[i]);
    }

    // Print all the recorded timestamps
    hero_print_timestamp();

    // Print the device cycles per region
    // for (int i = 0; i < hero_num_device_cycles; i++)
    //     printf("%u - ", hero_device_cycles[i]);
    // printf("\n");

    hero_dev_l3_free(NULL, A_virt, A_phys);
    hero_dev_l3_free(NULL, B_virt, B_phys);
    free(A_test);
    free(B_test);

    return 0;
}
