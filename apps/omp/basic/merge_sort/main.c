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

#define ALIGN_UP(size, align) ((size%align==0) ? size : size + align - (size%align))

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
    // Verification arrays
    DTYPE *in_test, *out_test = NULL;
    int do_map = 0;
    // Return
    int ret;

    int width = 16;

    if (argc > 1)
        width = strtol(argv[1], NULL, 10);
    if (argc > 2)
        do_map = strtol(argv[1], NULL, 10);

    // Verification arrays
    in_test =  aligned_alloc(0x1000, ALIGN_UP(width * sizeof(DTYPE), 0x1000));
    out_test = aligned_alloc(0x1000, ALIGN_UP(width * sizeof(DTYPE), 0x1000));

    hero_add_timestamp("enter_omp_init", __func__, 0);
    // Init Hero OpenMP runtime
    kernel_1();

    hero_add_timestamp("enter_prepare_data", __func__, 0);
    for (int i = 0; i < width; i++) {
        in_test[i] = (DTYPE)(rand() % 20);
    }

    hero_add_timestamp("enter_alloc_data", __func__, 0);
    // Note we only allocate 2*width so it can be used by an intermediary buffer by the device
    in = hero_dev_l3_malloc(NULL, 2 * width * sizeof(DTYPE), &in_phys);
    out = hero_dev_l3_malloc(NULL, width * sizeof(DTYPE), &out_phys);

    hero_add_timestamp("enter_copy_data", __func__, 0);
    memcpy(in, in_test, width*sizeof(DTYPE));

    hero_add_timestamp("enter_map_data", __func__, 0);
    if(!do_map) {
        in_iommu  =  (DTYPE *)hero_iommu_map_virt(NULL, width * sizeof(DTYPE), in_test);
        out_iommu =  (DTYPE *)hero_iommu_map_virt(NULL, width * sizeof(DTYPE), out_test);
    }
    asm volatile("fence");

    char toprint[128];
    snprintf(toprint, 128, "enter_omp_mergesort-%u", width);
    hero_add_timestamp(toprint, __func__, 0);
    ret = merge_sort(in, in_phys, out, out_phys, width);

    hero_add_timestamp("enter_verif", __func__, 0);
    quickSort(in_test, 0, width - 1);
    hero_add_timestamp("end_verif", __func__, 0);

    fence();

    // Verify result
    for (int i = 0; i < width; i++) {
        if(out[i] != in_test[i])
            printf("oops %f != %f\n\r", out[i], in_test[i]);
    }

    // Print all the recorded timestamps
    hero_print_timestamp();

    // Print the device cycles per region
    // for (int i = 0; i < hero_num_device_cycles; i++)
    //     printf("%u - ", hero_device_cycles[i]);
    // printf("\n");

    hero_dev_l3_free(NULL, in, in_phys);
    hero_dev_l3_free(NULL, out, out_phys);
    free(out_test);

    return 0;
}
