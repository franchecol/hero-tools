// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

#pragma once

#define DTYPE float
#define fdotp fdotp_opti_return_32b

#define MIN(A, B) (A < B ? A : B)
#define MAX_ELEM (128 - 32) * 1024 / (sizeof(DTYPE))

#define CORES 8
#define BUF_SIZE (256)

#ifdef __HERO_DEV

#ifdef __HERO_SNITCH_CLUSTER
#include "encoding.h"
#include "runtime.h"
#include "/usr/scratch2/wuerzburg/cykoenig/development/hero-tools/platforms/carfield/sw/tests/bare-metal/snitchd/common/printf.h"
#include "kernels/fdotp.h"
#endif

#endif // __HERO_DEV

#ifndef __HERO_SNITCH_CLUSTER
#error "Only working with Snitch Cluster"
#endif  // __HERO_SNITCH_CLUSTER

#ifdef __HERO_SNITCH_CLUSTER

#ifdef __HERO_DEV
#endif

#pragma omp declare target

#define MAX_COLS 50

__device DTYPE l1_rowbuf    [   CORES][BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_colbuf [2][MAX_COLS][BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_accbuf [2][   CORES][MAX_COLS] __attribute__((section(".noinit_l1")));
__device DTYPE l1_res       [   CORES][MAX_COLS] __attribute__((section(".noinit_l1")));

__attribute__((section(".noinit_l1"))) volatile uint32_t dma_timer = 0, dma_time = 0, all_timer = 0, all_time = 0, issue_timer = 0, issue_time = 0, compute_timer = 0, compute_time = 0;

#pragma omp end declare target

#define idx(A, m, n, p, i, j, k) ((A) + (k) * (m) * (n) * sizeof(DTYPE) + (i) * (n) * sizeof(DTYPE) + (j) * sizeof(DTYPE))

#define ZERO_MEM (0x51030000)

void sn_printrow(DTYPE *v, int n) {
    printf("  [ ");
    for(int i = 0; i < n; ++i)
        printf("%3.2f, ", v[i]);
    printf("]\n");
}

void sn_printmat(DTYPE *v, int m, int n, int el_per_row) {
    printf("[\n");
    for(int i = 0; i < m; ++i){
        sn_printrow(&v[i*n], el_per_row);
    }
    printf("]\n");
}

int gemm(uint32_t out_, uint32_t A_, uint32_t B_, uint32_t C_, int m_, int n_, int p_, DTYPE alpha_, DTYPE beta_)
{

    if (n_ > BUF_SIZE) {
        printf("Error : Size too large\n\r");
        return -1;
    }

    #pragma omp target device(1) map(to : out_, A_, B_, C_, m_, n_, p_, alpha_, beta_)
    {
        // Avoid argument optimization
        volatile uint32_t out__   = out_;
        volatile uint32_t A__     = A_;
        volatile uint32_t B__     = B_;
        volatile uint32_t C__     = C_;
        volatile uint32_t m__     = m_;
        volatile uint32_t n__     = n_;
        volatile uint32_t p__     = p_;
        volatile DTYPE    alpha__ = alpha_;
        volatile DTYPE    beta__  = beta_;

        // Device kernel
#ifdef __HERO_DEV

        const uint32_t out        = out_;
        const uint32_t A          = A_;
        const uint32_t B          = B_;
        const uint32_t C          = C_;
        const uint32_t m          = m_;
        const uint32_t n          = n_;
        const uint32_t p          = p_;
        const DTYPE    alpha      = alpha_; 
        const DTYPE    beta       = beta_;
        const uint32_t core_idx   = pulp_get_core_id();

        uint32_t issue_diff = 0;

        if (!m || !n || !p || !A || !B || !C || n > BUF_SIZE) {
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

        const uint32_t y = MIN(MAX_COLS, p);

        for (int i = 0; i < m; i += CORES) {

            const uint32_t rows_left       = m - i;
            const uint32_t rows_to_process = MIN(CORES, rows_left);

            
            if (core_idx == 8) {
                
                // printf("I         : %d%d\nRows left : %d\nRows proc : %d\n", i, rows_left, rows_to_process);
                
                issue_timer = pulp_get_timer();
                
                // Copy next #cores rows from A into l1_buf
                dma_start_2d_wideptr(l1_rowbuf, A + i * n * sizeof(DTYPE), n * sizeof(DTYPE), BUF_SIZE * sizeof(DTYPE), n * sizeof(DTYPE), rows_to_process);

                // Copy first y columns (actually rows, but transposed) from B into l1_vecs[0]
                dma_start_2d_wideptr(l1_colbuf[0], B, n * sizeof(DTYPE), BUF_SIZE * sizeof(DTYPE), n * sizeof(DTYPE), y);

                // Copy next #cores rows of first y columns of C into l1_accbuf[0]
                dma_start_2d_wideptr(l1_accbuf[0], C + i * p * sizeof(DTYPE), y * sizeof(DTYPE), MAX_COLS * sizeof(DTYPE), p * sizeof(DTYPE), rows_to_process);

                issue_time += pulp_get_timer() - issue_timer;
            }

            int itr = 0;

            for (int k = 0; k < p; k += y) {

                const uint32_t cols_left       = p - k;
                const uint32_t cols_to_process = MIN(y, cols_left);


                if (core_idx == 8) {
                    
                    // printf("Itr %d%d\n", itr);
                    // printf("K         : %d%d\nCols left : %d\nCols proc : %d\n", k, cols_left, cols_to_process);
                    
                    dma_timer = pulp_get_timer();
                    dma_wait_all();
                    dma_time += pulp_get_timer() - dma_timer;

                    pulp_barrier();

                    // Next iteration of double buffering
                    if (cols_left > y) {

                        issue_timer = pulp_get_timer();

                        // Copy next y columns (actually rows, but transposed) from B into l1_vecs[next]
                        dma_start_2d_wideptr(l1_colbuf[(itr+1)%2], B + (k + y) * n * sizeof(DTYPE), n * sizeof(DTYPE), BUF_SIZE * sizeof(DTYPE), n * sizeof(DTYPE), cols_to_process);
                        
                        // Copy next #cores rows of first y columns of C into l1_accbuf[next]
                        dma_start_2d_wideptr(l1_accbuf[(itr+1)%2], C + i * p * sizeof(DTYPE) + (k + y) * sizeof(DTYPE), cols_to_process * sizeof(DTYPE), MAX_COLS * sizeof(DTYPE), p * sizeof(DTYPE), rows_to_process);
                    
                        // issue_time += pulp_get_timer() - issue_timer;
                        issue_diff = pulp_get_timer() - issue_timer;
                    }
                }

                if (core_idx < 8) {
                    
                    pulp_barrier();
                    
                    asm volatile ("fence");

                    if(core_idx == 0) compute_timer = pulp_get_timer();

                    for(int z = 0; z < cols_to_process; ++z) {
                        register DTYPE res = 0;
                        res = fdotp(l1_rowbuf[core_idx], l1_colbuf[itr%2][z], n);
                        res *= alpha;
                        res += beta * l1_accbuf[itr%2][core_idx][z];
                        l1_res[core_idx][z] = res;
                    }

                    asm volatile ("fence");
                }

                pulp_barrier();

               if(core_idx == 0) compute_time += pulp_get_timer() - compute_timer;

                if(core_idx == 8) {
                   uint32_t compute_diff = (pulp_get_timer() - compute_timer);
                    // Copy out data
                   issue_timer = pulp_get_timer();
                    dma_start_2d_wideptr(out + i * p * sizeof(DTYPE) + k * sizeof(DTYPE), l1_res, cols_to_process * sizeof(DTYPE), p * sizeof(DTYPE), MAX_COLS * sizeof(DTYPE), rows_to_process);
                   issue_time += pulp_get_timer() - issue_timer + (issue_diff - compute_diff) * (issue_diff > compute_diff);
                }

                itr++;
            }

        }

        pulp_barrier();

        if(core_idx == 8) {
            all_time = pulp_get_timer() - all_timer;
            printf("%x Tot : %u Dma : %u Issue : %u Compute : %u\n", all_time, dma_time, issue_time, compute_time);
        }

        pulp_barrier();

#endif

        omp_exit:;
    }

    return 0;
}

#endif // __HERO_SNITCH_CLUSTER
