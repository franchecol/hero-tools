// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

#pragma once

#define DTYPE float
#define fdotp fdotp_opti_32b

#define MIN(A, B) (A < B ? A : B)
#define MAX_ELEM (128 - 32) * 1024 / (sizeof(DTYPE))

#define CORES 8
#define BUF_SIZE (512)

#ifdef __HERO_DEV

#ifdef __HERO_SNITCH_CLUSTER
#include "encoding.h"
#include "runtime.h"
#include "/usr/scratch2/wuerzburg/cykoenig/development/hero-tools/platforms/carfield/sw/tests/bare-metal/snitchd/common/printf.h"
#include "kernels/fdotp.h"
#endif

#endif // __HERO_DEV

#ifndef __HERO_SNITCH_CLUSTER
#error "Only support Snitch Cluster"
#endif  // __HERO_SNITCH_CLUSTER

#ifdef __HERO_SNITCH_CLUSTER

#pragma omp declare target

__device DTYPE l1_buf  [2][CORES * BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_vec     [        BUF_SIZE] __attribute__((section(".noinit_l1")));

__attribute__((section(".noinit_l1"))) volatile uint32_t dma_timer = 0, dma_time = 0, all_timer = 0, all_time = 0, issue_timer = 0, issue_time = 0, compute_timer = 0, compute_time = 0;

#pragma omp end declare target

// Device helper function
#ifdef __HERO_DEV

int matvec(const uint32_t out, const uint32_t x, const uint32_t A, const DTYPE alpha, const int n, const int d)
{
    const uint32_t core_idx = pulp_get_core_id();

    if(core_idx == 8) {
        issue_timer = pulp_get_timer();
        dma_start_1d_wideptr(&l1_vec[0], x, n * sizeof(DTYPE));
        dma_start_1d_wideptr(l1_buf[0], A, n * CORES * sizeof(DTYPE));
        issue_time += pulp_get_timer() - issue_timer;
    }

    int itr = 0;

    for (int I = 0; I < d; I += CORES) {
        
        const int rows_left = d - I;
        
        if(core_idx == 8) {
            dma_timer = pulp_get_timer();
            dma_wait_all();
            dma_time += pulp_get_timer() - dma_timer;
            pulp_barrier();
            if(rows_left > CORES){
                issue_timer = pulp_get_timer();
                dma_start_1d_wideptr(l1_buf[(itr+1)%2], A + n * sizeof(DTYPE) * (I + CORES), n * MIN(rows_left - CORES, CORES) * sizeof(DTYPE));
                issue_time += pulp_get_timer() - issue_timer;
            }
        }

        if(core_idx < 8) {
            pulp_barrier();
            asm volatile ("fence");
            if(core_idx == 0) compute_timer = pulp_get_timer();
            fdotp(l1_vec, &(l1_buf[itr % 2][core_idx * n]), &((DTYPE *)out)[I + core_idx], n);
            ((DTYPE *)out)[I + core_idx] *= alpha;
            asm volatile ("fence");
        }
        pulp_barrier();
        if(core_idx == 0) compute_time += pulp_get_timer() - compute_timer;
        
        itr++;
    }

    return 0;
}

#endif

#pragma omp declare target
__device DTYPE l1_tmp_1 [BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_tmp_2 [BUF_SIZE] __attribute__((section(".noinit_l1")));
#pragma omp end declare target

int gesummv(uint32_t out_, uint32_t A_, uint32_t B_, uint32_t x_, uint32_t y_, DTYPE alpha_, DTYPE beta_, int n_, int d_)
{

    if (n_ * 9 > MAX_ELEM) {
        printf("Error : Size too large\n\r");
        return -1;
    }

    #pragma omp target device(1) map(to : n_, d_, out_, A_, B_, x_, y_)
    {
        // Avoid argument optimization
        volatile uint32_t out__    = out_;
        volatile uint32_t A__      = A_;
        volatile uint32_t B__      = B_;
        volatile uint32_t x__      = x_;
        volatile uint32_t y__      = y_;
        volatile DTYPE    alpha__  = alpha_;
        volatile DTYPE    beta__   = beta_;
        volatile uint32_t n__      = n_;
        volatile uint32_t d__      = d_;

        // Device kernel
#ifdef __HERO_DEV

        const uint32_t n        = n_;
        const uint32_t d        = d_;
        const uint32_t out      = out_;
        const uint32_t A        = A_;
        const uint32_t B        = B_;
        const uint32_t x        = x_;
        const uint32_t y        = y_;
        const DTYPE    alpha    = alpha_;
        const DTYPE    beta     = beta_;
        const uint32_t core_idx = pulp_get_core_id();

        if (!n || !d || !out || !A || !B || !x || !y || n > BUF_SIZE) {
            if(core_idx == 0) printf("Wrong parameters\r\n");
            goto omp_exit;
        }

        if (core_idx == 0) { compute_time = 0; }
        if (core_idx == 8) { 
            dma_time     = 0;
            issue_time   = 0;
            all_time     = 0;
        }
        
        pulp_barrier();

        if(core_idx == 8) all_timer = pulp_get_timer();

        matvec(l1_tmp_1, x, A, alpha, n, d);
        
        pulp_barrier();
        
        matvec(l1_tmp_2, y, B, beta, n, d);
        
        pulp_barrier();
        
        if(core_idx == 8) {
            
            compute_timer = pulp_get_timer();
            for (int i = 0; i < d; ++i)
                l1_tmp_1[i] += l1_tmp_2[i];
            compute_time += pulp_get_timer() - compute_timer;

            issue_timer = pulp_get_timer();
            dma_start_1d_wideptr((DTYPE *)out, l1_tmp_1, d * sizeof(DTYPE));
            issue_time += pulp_get_timer() - issue_timer;
            
            dma_timer = pulp_get_timer();
            dma_wait_all();
            dma_time += pulp_get_timer() - dma_timer;
        
        }

        pulp_barrier();

        if(core_idx == 8) {
            all_time = pulp_get_timer() - all_timer;
            printf("%x Tot : %u Dma : %u Issue : %u Compute : %u\n\r", all_time, dma_time, issue_time, compute_time);
        }

#endif

        omp_exit:;
    }

    return 0;
}

#endif // __HERO_SNITCH_CLUSTER
