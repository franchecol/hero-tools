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
#include "gesummv.h"
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
    printf("]\r\n");
}

void printmat(const char *name, DTYPE *v, int m, int n) {
    printf("Matrix %s: [\r\n", name);
    for(int i = 0; i < m; ++i){
        printvec("", &v[i*n], n);
    }
    printf("]\r\n");
}

/*
 * Gesummv : alpha*A*x + beta*B*y
 * A       : Input matrix A
 * B       : Input matrix B
 * x       : Input vector x
 * y       : Input vector y
 * alpha   : Input scalar alpha
 * beta    : Input scalar beta
 * res     : Output vector
*/

#define ALIGN_UP(size, align) ((size%align==0) ? size : size + align - (size%align))

int main(int argc, char *argv[])
{
    // Physical addresses
    uintptr_t A_phys, B_phys, x_phys, y_phys, out_phys;
    // Virtual addresses
    DTYPE *A_virt = NULL, *B_virt = NULL, *x_virt = NULL, *y_virt = NULL, *out_virt = NULL;
    // Verification matrices / vectors
    DTYPE *A_test = NULL, *B_test = NULL, *x_test = NULL, *y_test = NULL, *out_test = NULL;
    // Device virtual addresses
    DTYPE *A_iommu = NULL, *B_iommu = NULL, *x_iommu = NULL, *y_iommu = NULL, *out_iommu = NULL;
    // Scalar coefficients
    DTYPE alpha = 1.0f, beta = 1.0f;
    // Do / Don't map IOMMU flag
    int do_map;
    // Return
    int ret;
    // sprintf buffer
    char toprint[128];

    int height = 16;

    if (argc > 1)
        height = strtol(argv[1], NULL, 10);
    int width = height;
    if (argc > 2)
        width = strtol(argv[2], NULL, 10);
    if (argc > 3)
        alpha = atof(argv[3]);
    if (argc > 4)
        beta = atof(argv[4]);
    if (argc > 5)
        do_map = strtol(argv[5], NULL, 10);

    // Verification matrices
    A_test   = aligned_alloc(0x1000, ALIGN_UP(height * width * sizeof(DTYPE), 0x1000));
    B_test   = aligned_alloc(0x1000, ALIGN_UP(height * width * sizeof(DTYPE), 0x1000));
    x_test   = aligned_alloc(0x1000, ALIGN_UP(         width * sizeof(DTYPE), 0x1000));
    y_test   = aligned_alloc(0x1000, ALIGN_UP(         width * sizeof(DTYPE), 0x1000));
    out_test = aligned_alloc(0x1000, ALIGN_UP(height         * sizeof(DTYPE), 0x1000));

    // Init Hero OpenMP runtime
    hero_add_timestamp("enter_init_omp", __func__, 0);
    kernel_1();

    // Prepare data in Linux's virtual memory region
    hero_add_timestamp("enter_prepare_data", __func__, 0);
    for (int i = 0; i < height; i++){
        for (int j = 0; j < width; j++){
            A_test[i * width + j] = (DTYPE)(i * width + j);
            B_test[i * width + j] = (DTYPE)(i * width + j);
        }
    }
    for (int j = 0; j < width; j++){
        x_test[j] = (j == 0) ? (DTYPE)(1) : (DTYPE)(0);
        y_test[j] = (j == 0) ? (DTYPE)(1) : (DTYPE)(0);
    }
    for (int i = 0; i < height; i++){
        out_test[i] = (DTYPE)(0);
    }

    // Allocate data in upper phisical memory region
    hero_add_timestamp("enter_alloc_data", __func__, 0);
    A_virt   = hero_dev_l3_malloc(NULL, height *width * sizeof(DTYPE),   &A_phys);
    B_virt   = hero_dev_l3_malloc(NULL, height *width * sizeof(DTYPE),   &B_phys);
    x_virt   = hero_dev_l3_malloc(NULL,         width * sizeof(DTYPE),   &x_phys);
    y_virt   = hero_dev_l3_malloc(NULL,         width * sizeof(DTYPE),   &y_phys);
    out_virt = hero_dev_l3_malloc(NULL, height        * sizeof(DTYPE), &out_phys);

    // Copy data to physical memory region
    hero_add_timestamp("enter_copy_data", __func__, 0);
    memcpy(A_virt, A_test, height * width * sizeof(DTYPE));
    memcpy(B_virt, B_test, height * width * sizeof(DTYPE));
    memcpy(x_virt, x_test,          width * sizeof(DTYPE));
    memcpy(y_virt, y_test,          width * sizeof(DTYPE));

    // Map allocated data into device IOMMU
    hero_add_timestamp("enter_map_data", __func__, 0);
    if (do_map) {
        A_iommu   = (DTYPE *)hero_iommu_map_virt(NULL, height * width * sizeof(DTYPE),   A_test);
        B_iommu   = (DTYPE *)hero_iommu_map_virt(NULL, height * width * sizeof(DTYPE),   B_test);
        x_iommu   = (DTYPE *)hero_iommu_map_virt(NULL,          width * sizeof(DTYPE),   x_test);
        y_iommu   = (DTYPE *)hero_iommu_map_virt(NULL,          width * sizeof(DTYPE),   y_test);
        out_iommu = (DTYPE *)hero_iommu_map_virt(NULL, height         * sizeof(DTYPE), out_test);
    }
    asm volatile("fence");

    // Offload
    snprintf(toprint, 128, "enter_omp_gesummv-%u-%u", height, width);
    hero_add_timestamp(toprint, __func__, 0);
    ret = gesummv(out_phys, A_phys, B_phys, x_phys, y_phys, alpha, beta, width, height);

    // Execution on host
    hero_add_timestamp("enter_verif", __func__, 0);
    for (int i = 0; i < height; i++) {
        DTYPE val = 0.0f;
        for (int j = 0; j < width; j++)
            val += alpha * A_test[i * width + j] * x_test[j] + beta * B_test[i * width + j] * y_test[j];
        out_test[i] = val;
    }
    hero_add_timestamp("end_verif", __func__, 0);

    asm volatile("fence");

    // Verify result
    for (int i = 0; i < height; i++) {
        if (out_test[i] != out_virt[i])
            printf("nope %i (%f != %f)\n\r", i, out_test[i], out_virt[i]);
    }

    // Print all the recorded timestamps
    hero_print_timestamp();

    // Print the device cycles per region
    // for (int i = 0; i < hero_num_device_cycles; i++)
    //     printf("%u - ", hero_device_cycles[i]);
    // printf("\n");

    hero_dev_l3_free(NULL,   A_virt,   A_phys);
    hero_dev_l3_free(NULL,   B_virt,   B_phys);
    hero_dev_l3_free(NULL,   x_virt,   x_phys);
    hero_dev_l3_free(NULL,   y_virt,   y_phys);
    hero_dev_l3_free(NULL, out_virt, out_phys);
    free(  A_test);
    free(  B_test);
    free(  x_test);
    free(  y_test);
    free(out_test);

    return 0;
}
