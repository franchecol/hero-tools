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

#include "utils.h"

#include <libhero/hero_api.h>

#define ALIGN_UP(size, align) ((size%align==0) ? size : size + align - (size%align))
#define MIN(A, B) (((A)<(B))?(A):(B))

int axpy(uint32_t x_phys, uint32_t y_phys, float alpha, uint32_t n);

int main(int argc, char *argv[])
{
    // Physical addresses
    uintptr_t x_phys, y_phys;
    // Virtual addresses
    float *x_virt = NULL, *y_virt = NULL;
    // Verification matrices / vectors
    float *x_test = NULL, *y_test = NULL;
    // Device virtual addresses
    float *x_iommu = NULL, *y_iommu = NULL;
    // Do / Don't map IOMMU flag
    int do_map = 0;
    // Return
    int ret;
    // sprintf buffer
    char toprint[128];

    int n       = 16;
    float alpha = 1.0f;
    int noise   = 0;

    if (argc > 1)
        n = strtol(argv[1], NULL, 10);
    if (argc > 2)
        alpha = atof(argv[2]);
    if (argc > 3)
        do_map = strtol(argv[3], NULL, 10);
    if (argc > 4)
        noise = strtol(argv[4], NULL, 10);

    // Verification matrices
    x_test   = aligned_alloc(0x1000, ALIGN_UP(n * sizeof(float), 0x1000));
    y_test   = aligned_alloc(0x1000, ALIGN_UP(n * sizeof(float), 0x1000));

    // Init Hero OpenMP runtime
    hero_add_timestamp("enter_init_omp", __func__, 0);
    init_omp_target();

    // Prepare data in Linux's virtual memory region
    hero_add_timestamp("enter_prepare_data", __func__, 0);

    for (int i = 0; i < n; ++i) {
        x_test[i] = (float) (fast_rand()%30 / 4);
        y_test[i] = (float) (fast_rand()%30 / 4);
    }

    // Allocate data in upper physical memory region
    if(!do_map) {
        hero_add_timestamp("enter_alloc_data", __func__, 0);
        x_virt   = hero_dev_l3_malloc(NULL, n * sizeof(float),   &x_phys);
        y_virt   = hero_dev_l3_malloc(NULL, n * sizeof(float),   &y_phys);
    }

    // Copy data to physical memory region
    if(!do_map) {
        hero_add_timestamp("enter_copy_data", __func__, 0);
        memcpy(x_virt, x_test, n  * sizeof(float));
        memcpy(y_virt, y_test, n  * sizeof(float));
    }

    // Map allocated data into device IOMMU
    if (do_map) {
        hero_add_timestamp("enter_map_data", __func__, 0);
        x_virt = (float *)hero_iommu_map_virt(NULL, n * sizeof(float), x_test);
        y_virt = (float *)hero_iommu_map_virt(NULL, n * sizeof(float), y_test);
    }

    asm volatile("fence");

    // Offload 1 (pre-heat instruction caches)
    snprintf(toprint, 128, "enter_cold_omp_axpy-%u", n);
    hero_add_timestamp(toprint, __func__, 0);
    ret = axpy((uint32_t)x_phys, (uint32_t)y_phys, alpha, (uint32_t)n);

    // Offload 2
    snprintf(toprint, 128, "enter_hot_omp_axpy-%u", n);
    hero_add_timestamp(toprint, __func__, 0);
    ret = axpy((uint32_t)x_phys, (uint32_t)y_phys, alpha, (uint32_t)n);

    // Execution on host
    hero_add_timestamp("enter_verif", __func__, 0);
    for (long i=0; i < n; i+=4) {
       y_test[i]   = alpha * x_test[i]   + y_test[i]   ;
       y_test[i+1] = alpha * x_test[i+1] + y_test[i+1] ;
       y_test[i+2] = alpha * x_test[i+2] + y_test[i+2] ;
       y_test[i+3] = alpha * x_test[i+3] + y_test[i+3] ;
    }
    hero_add_timestamp("end_verif", __func__, 0);

    asm volatile("fence");

    // Verify result
    for (int i = 0; i < n; i++) {
        if (y_test[i] != y_virt[i]) {
            printf("nope %i (%f != %f)\n", i, y_test[i], y_virt[i]);
            break;
        }
    }

    // Print all the recorded timestamps
    hero_print_timestamp();

    // Print the device cycles per region
    // for (int i = 0; i < hero_num_device_cycles; i++)
    //     printf("%u - ", hero_device_cycles[i]);
    // printf("\n");

    hero_dev_l3_free(NULL,   x_virt,   x_phys);
    hero_dev_l3_free(NULL,   y_virt,   y_phys);
    free(  x_test);
    free(  y_test);

    return 0;
}
