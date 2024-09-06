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
#include "merge_sort.h"
#include "merge_sort_host.h"
///// END includes /////

void kernel_1()
{
#pragma omp target device(1)
    asm volatile("nop");
}

int main(int argc, char *argv[])
{
    // Physical addresses
    uintptr_t in_phys, out_phys;
    // Virtual addresses
    DTYPE *in = NULL, *out = NULL, *in_iommu = NULL, *out_iommu = NULL;
    // Verification matrices
    DTYPE *in_test, *out_test = NULL;
    // Return
    int ret;

    int width = 16;

    if (argc > 1)
        width = strtol(argv[1], NULL, 10);

    // Init Hero OpenMP runtime
    kernel_1();

    // Verification matrices
    in_test = malloc(width * sizeof(DTYPE));
    out_test = malloc(width * sizeof(DTYPE));
    // Note in and out IOMMU don't need to be diff from in and out test
    in_iommu = malloc(width * sizeof(DTYPE));
    out_iommu = malloc(width * sizeof(DTYPE));
    // Prepare data
    for (int i = 0; i < width; i++) {
        in_test[i] = (DTYPE)(rand() % 20);
        in_iommu[i] = in_test[i];
    }

    hero_add_timestamp("prepare_data", __func__, 0);
    // Device matrices
    in = hero_dev_l3_malloc(NULL, 2 * width * sizeof(DTYPE), &in_phys);
    out = hero_dev_l3_malloc(NULL, width * sizeof(DTYPE), &out_phys);
    // Prepare data
    for (int i = 0; i < width; i++) {
        in[i] = in_test[i];
    }

    hero_add_timestamp("prepare_data_iommu", __func__, 0);
    // Device matrices
    // in  =  (DTYPE *)hero_iommu_map_virt(NULL, 2 * width * sizeof(DTYPE), in_iommu);
    // out = (DTYPE *)hero_iommu_map_virt(NULL, width * sizeof(DTYPE)    , out_iommu);
    //asm volatile("fence");

    // printf("-- %llx - %llx - %u --\n\r", in_phys, out_phys, width);

    // Offload
    ret = merge_sort(in, in_phys, out, out_phys, width);

    hero_add_timestamp("verif", __func__, 0);
    quickSort(in_test, 0, width - 1);
    hero_add_timestamp("end_verif", __func__, 0);

    fence();

    // Execution on host
    //char toprint[128];
    //snprintf(toprint, 128, "enter_omp_verify_matvec-%u", width);
    //hero_add_timestamp(toprint, __func__, 0);
    //asm volatile("fence");
    //for (int i = 0; i < height; i++) {
    //    DTYPE val = 0.0f;
    //    for (int j = 0; j < width; j++)
    //        val += C_test[i * width + j] * D_test[j];
    //    E_test[i] = val;
    //}
    //snprintf(toprint, 128, "enter_end", width);
    //asm volatile("fence");
    //hero_add_timestamp(toprint, __func__, 0);

    // Verify result
    for (int i = 0; i < width; i++) {
        if(out[i] != in_test[i])
            printf("oops %f != %f\n\r", out[i], in_test[i]);
        // printf(" %u -", out[i]);
        // printf(" %u -", in_test[i]);
    }
    //printf("\n\r");

    // Print all the recorded timestamps
    hero_print_timestamp();

    // Print the device cycles per region
    //for (int i = 0; i < hero_num_device_cycles; i++)
    //    printf("%u - ", hero_device_cycles[i]);
    //printf("\n");

    hero_dev_l3_free(NULL, in, in_phys);
    hero_dev_l3_free(NULL, out, out_phys);
    free(out_test);

    return 0;
}
