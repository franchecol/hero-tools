// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

////// HERO_1 includes /////
#ifdef __HERO_DEV
extern int* hero_device_cycles;
extern int hero_num_device_cycles;
#include "encoding.h"
#include "runtime.h"
#include "/usr/scratch2/wuerzburg/cykoenig/development/hero-tools/platforms/carfield/sw/tests/bare-metal/snitchd/common/printf.h"

#define BUF_SIZE 256
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

extern volatile int noise_amount;

#endif
///// ALL includes /////
#include "hero_64.h"
#include "iommu.h"
#define DTYPE float
#define ALIGN_UP(size, align) ((size%align==0) ? size : size + align - (size%align))
#define MIN(A, B) (((A)<(B))?(A):(B))

///// END includes /////

void kernel_1()
{
#pragma omp target device(1)
    asm volatile("nop");
}

int axpy(uint32_t x_phys, uint32_t y_phys, DTYPE alpha, uint32_t n);


int main(int argc, char *argv[])
{
    // Physical addresses
    uintptr_t x_phys, y_phys;
    // Virtual addresses
    DTYPE *x_virt = NULL, *y_virt = NULL;
    // Verification matrices / vectors
    DTYPE *x_test = NULL, *y_test = NULL;
    // Device virtual addresses
    DTYPE *x_iommu = NULL, *y_iommu = NULL;
    // Do / Don't map IOMMU flag
    int do_map = 0;
    // Return
    int ret;
    // sprintf buffer
    char toprint[128];

    int noise = 0;

    int n       = 16;
    DTYPE alpha = 1.0f;

    if (argc > 1)
        n = strtol(argv[1], NULL, 10);
    if (argc > 2)
        alpha = atof(argv[2]);
    if (argc > 3)
        do_map = strtol(argv[3], NULL, 10);
    if (argc > 4)
        noise = strtol(argv[4], NULL, 10);

#ifndef __HERO_DEV
    noise_amount = noise;
#endif

    // Get access to IOMMU configuration registers (devmap)
    uint64_t iommu_base_virt = iommu_devmap();

    // Reset IOMMU counters
    iommu_reset_counters(iommu_base_virt);

    // Verification matrices
    x_test   = aligned_alloc(0x1000, ALIGN_UP(n * sizeof(DTYPE), 0x1000));
    y_test   = aligned_alloc(0x1000, ALIGN_UP(n * sizeof(DTYPE), 0x1000));

    // Init Hero OpenMP runtime
    hero_add_timestamp("enter_init_omp", __func__, 0);
    kernel_1();

    // Prepare data in Linux's virtual memory region
    hero_add_timestamp("enter_prepare_data", __func__, 0);

    for (int i = 0; i < n; ++i) {
        x_test[i] = (DTYPE) (rand()%30 / 4);
        y_test[i] = (DTYPE) (rand()%30 / 4);
    }

    // Allocate data in upper phisical memory region
    hero_add_timestamp("enter_alloc_data", __func__, 0);
    x_virt   = hero_dev_l3_malloc(NULL, n * sizeof(DTYPE),   &x_phys);
    y_virt   = hero_dev_l3_malloc(NULL, n * sizeof(DTYPE),   &y_phys);

    // Copy data to physical memory region
    hero_add_timestamp("enter_copy_data", __func__, 0);
    memcpy(x_virt, x_test, n  * sizeof(DTYPE));
    memcpy(y_virt, y_test, n  * sizeof(DTYPE));

    // Map allocated data into device IOMMU
    hero_add_timestamp("enter_map_data", __func__, 0);
    if (do_map) {
        x_iommu = (DTYPE *)hero_iommu_map_virt(NULL, n * sizeof(DTYPE), x_test);
    }

    asm volatile("fence");

    // Offload 1 (pre-heat instruction caches)
    snprintf(toprint, 128, "enter_cold_omp_axpy-%u", n);
    hero_add_timestamp(toprint, __func__, 0);
    ret = axpy((uint32_t)x_phys, (uint32_t)y_phys, alpha, (uint32_t)n);

    // Print IOMMU stats and reset counters
    hero_add_timestamp("reset_iommmu_counters", __func__, 0);
    iommu_print_stats(iommu_base_virt);
    iommu_reset_counters(iommu_base_virt);
    // Also, copy input data again
    memcpy(x_virt, x_test, n  * sizeof(DTYPE));
    memcpy(y_virt, y_test, n  * sizeof(DTYPE));

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

    // Print IOMMU stats
    iommu_print_stats(iommu_base_virt);

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

#pragma omp declare target

#ifdef __HERO_DEV
__device DTYPE l1_buf_x  [2][8][BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_buf_y  [2][8][BUF_SIZE] __attribute__((section(".noinit_l1")));

__attribute__((section(".noinit_l1"))) volatile uint32_t dma_timer = 0, dma_time = 0, all_timer = 0, all_time = 0, issue_timer = 0, issue_time = 0, compute_timer = 0, compute_time = 0;

void dev_axpy(uint32_t x_phys, uint32_t y_phys, DTYPE alpha, uint32_t n) {
    
    const uint32_t core_idx = pulp_get_core_id();

    uint32_t issue_diff = 0;

    //if(core_idx == 0)
    //    print("%x %x %x %f %x\n\r", x_phys, y_phys, alpha, n);

    if (!x_phys || !y_phys || !n || n % (8*BUF_SIZE) != 0) {
        if(core_idx == 0)
            printf("Error!\n\r");
        return;
    }

    if (core_idx == 0) { compute_time = 0; }
    if (core_idx == 8) { 
        dma_time     = 0;
        issue_time   = 0;
        all_time     = 0;
    }

    pulp_barrier();

    if(core_idx == 8) all_timer = pulp_get_timer();

    if(core_idx == 8) {
        issue_timer = pulp_get_timer();
        __dma_start_1d_wideptr_base((uint64_t) l1_buf_x[0], (uint64_t) x_phys, 8*BUF_SIZE*sizeof(DTYPE), 0);
        __dma_start_1d_wideptr_base((uint64_t) l1_buf_y[0], (uint64_t) y_phys, 8*BUF_SIZE*sizeof(DTYPE), 0);
        issue_time += pulp_get_timer() - issue_timer;
    }

    int itr = 0;
    for(int i = 0; i < n; i += 8*BUF_SIZE) {
        int rest = n - 8*BUF_SIZE - i;
        
        if(core_idx == 8) {
            dma_timer = pulp_get_timer();
            dma_wait_all();
            dma_time += pulp_get_timer() - dma_timer;
            
            pulp_barrier();
            
            issue_timer = pulp_get_timer();
            if(rest > 0) {
                __dma_start_1d_wideptr_base((uint64_t) l1_buf_x[(itr+1)%2], x_phys + (i+8*BUF_SIZE)*sizeof(DTYPE), 8*BUF_SIZE*sizeof(DTYPE), 0);
                __dma_start_1d_wideptr_base((uint64_t) l1_buf_y[(itr+1)%2], y_phys + (i+8*BUF_SIZE)*sizeof(DTYPE), 8*BUF_SIZE*sizeof(DTYPE), 0);
            }
            issue_diff = pulp_get_timer() - issue_timer;
        } else {
            
            pulp_barrier();

            if(core_idx == 0) compute_timer = pulp_get_timer();

            // Don't accumulate in first iteration
            asm volatile("mv t0, zero\n"
                 // Don't accumulate in first iteration
                 "addi t0, t0, 1\n\r"
                 "flw ft1, 0(%[a]) \n"
                 "add %[a], %[a], 4 \n"
                 "flw ft2, 0(%[b]) \n"
                 "fmadd.s ft2, %[alpha], ft1, ft2 \n"
                 "fsw ft2, 0(%[b]) \n"
                 "add %[b], %[b], 4 \n"
                 "blt   t0, %[n], -28 \n"
                 :
                 : [n] "r"(BUF_SIZE), [a] "r"(&l1_buf_x[itr%2][core_idx]), [b] "r"(&l1_buf_y[itr%2][core_idx]), [alpha] "f"(alpha)
                 : "ft1", "ft2", "t0");

            //for(int i = 0; i < BUF_SIZE; i++)
            //    l1_buf_y[itr%2][core_idx][i] = alpha * l1_buf_x[itr%2][core_idx][i] + l1_buf_y[itr%2][core_idx][i];
        }

        pulp_barrier();

        if(core_idx == 0) compute_time += pulp_get_timer() - compute_timer;
        
        if(core_idx == 8) {
            uint32_t compute_diff = (pulp_get_timer() - compute_timer);
             // Copy out data
            issue_timer = pulp_get_timer();
            __dma_start_1d_wideptr_base(y_phys + i*sizeof(DTYPE), (uint64_t) &l1_buf_y[itr%2], 8*BUF_SIZE*sizeof(DTYPE), 0);
            issue_time += pulp_get_timer() - issue_timer + (issue_diff - compute_diff) * (issue_diff > compute_diff);
        }
        itr++;
    }
    
    pulp_barrier();

    if(core_idx == 8) {
        all_time = pulp_get_timer() - all_timer;
        printf("%x Tot : %u Dma : %u Issue : %u Compute : %u\n", all_time, dma_time, issue_time, compute_time);
    }

    pulp_barrier();
}

#endif

#pragma omp end declare target

int axpy(uint32_t x_phys, uint32_t y_phys, DTYPE alpha, uint32_t n) {
    #pragma omp target device(1) map(to:x_phys, y_phys, alpha, n)
    {
        volatile uint32_t _x_phys = x_phys;
        volatile uint32_t _y_phys = y_phys;
        volatile uint32_t _alpha  = alpha;
        volatile uint32_t _n      = n;
#ifdef __HERO_DEV
        dev_axpy(x_phys, y_phys, alpha, n);
#endif
    }

}
