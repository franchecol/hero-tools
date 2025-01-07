// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

//////////////////////////////
// Host wrapper             //
//////////////////////////////

#include <inttypes.h>

void dev_axpy(uint32_t x_phys, uint32_t y_phys, float alpha, uint32_t n);


int axpy(uint32_t x_phys, uint32_t y_phys, float alpha, uint32_t n) {
    #pragma omp target device(1) map(to:x_phys, y_phys, alpha, n)
    {
        (volatile uint32_t) x_phys;
        (volatile uint32_t) y_phys;
        (volatile float) alpha;
        (volatile uint32_t) n;
#ifdef __HERO_DEV
        dev_axpy(x_phys, y_phys, alpha, n);
#endif
    }

}

//////////////////////////////
// Device Kernel            //
//////////////////////////////

#ifdef __HERO_DEV

#include "encoding.h"
#include "runtime.h"
#include "printf.h"
#include "printf.h"
#include "hero_64.h"

#define NUM_CORES 8
#define BUF_SIZE 64

#pragma omp declare target

// Double buffered compute buffers for Snitch cores
__device float l1_buf_x  [2][NUM_CORES][BUF_SIZE] __attribute__((section(".noinit_l1")));
__device float l1_buf_y  [2][NUM_CORES][BUF_SIZE] __attribute__((section(".noinit_l1")));

__attribute__((section(".noinit_l1"))) volatile uint32_t dma_timer, dma_time, all_timer, all_time, issue_timer, issue_time, compute_timer, compute_time;

void dev_axpy(uint32_t x_phys, uint32_t y_phys, float alpha, uint32_t n) {
    
    const uint32_t core_idx = pulp_get_core_id();

    uint32_t issue_diff = 0;

    if(core_idx == 0)
        printf("%x %lx %lx %lx %lx\n\r", &x_phys, &y_phys, &alpha, &n);
    if(core_idx == 0)
        printf("%x %lx %lx %f %u\n\r", x_phys, y_phys, alpha, n);

    //return;

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
        __dma_start_1d_wideptr_base((uint64_t) l1_buf_x[0], (uint64_t) x_phys, 8*BUF_SIZE*sizeof(float), 0);
        __dma_start_1d_wideptr_base((uint64_t) l1_buf_y[0], (uint64_t) y_phys, 8*BUF_SIZE*sizeof(float), 0);
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
                __dma_start_1d_wideptr_base((uint64_t) l1_buf_x[(itr+1)%2], x_phys + (i+8*BUF_SIZE)*sizeof(float), 8*BUF_SIZE*sizeof(float), 0);
                __dma_start_1d_wideptr_base((uint64_t) l1_buf_y[(itr+1)%2], y_phys + (i+8*BUF_SIZE)*sizeof(float), 8*BUF_SIZE*sizeof(float), 0);
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
            __dma_start_1d_wideptr_base(y_phys + i*sizeof(float), (uint64_t) &l1_buf_y[itr%2], 8*BUF_SIZE*sizeof(float), 0);
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

#pragma omp end declare target

#endif
