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
#define BUF_SIZE (258)

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
#endif // __HERO_SNITCH_CLUSTER

#ifdef __HERO_SNITCH_CLUSTER

#pragma omp declare target

__device DTYPE l1_buf [2][3][CORES+2][BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_res       [  CORES][BUF_SIZE] __attribute__((section(".noinit_l1")));

__attribute__((section(".noinit_l1"))) volatile uint32_t dma_timer = 0, dma_time = 0, all_timer = 0, all_time = 0, issue_timer = 0, issue_time = 0, compute_timer = 0, compute_time = 0;

#pragma omp end declare target

#define idx(A, m, n, p, i, j, k) ((A) + (k) * (m) * (n) * sizeof(DTYPE) + (i) * (n) * sizeof(DTYPE) + (j) * sizeof(DTYPE))

#define ZERO_MEM (0x51030000)

int heat3d(uint32_t A_, uint32_t B_, int m_, int n_, int p_, DTYPE alpha_, int iterations_)
{

    if (n_ > BUF_SIZE) {
        printf("Error : Size too large\n\r");
        return -1;
    }

    #pragma omp target device(1) map(to : m_, n_, p_, A_, B_, alpha_, iterations_)
    {
        // Avoid argument optimization
        volatile uint32_t A__          = A_;
        volatile uint32_t B__          = B_;
        volatile uint32_t m__          = m_;
        volatile uint32_t n__          = n_;
        volatile uint32_t p__          = p_;
        volatile DTYPE    alpha__      = alpha_;
        volatile uint32_t iterations__ = iterations_;

        // Device kernel
#ifdef __HERO_DEV

        const uint32_t m          = m_;
        const uint32_t n          = n_;
        const uint32_t p          = p_;
        const DTYPE    alpha      = alpha_; 
        const uint32_t iterations = iterations_;
        const uint32_t A          = A_;
        const uint32_t B          = B_;
        const uint32_t core_idx   = pulp_get_core_id();

        uint32_t M_in, M_out;

        if (!m || !n || !p || !A || !B || n > BUF_SIZE) {
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

        const uint32_t i_offset = n * sizeof(DTYPE);
        const uint32_t k_offset = m * n * sizeof(DTYPE);

        // Input and output buffers, (input passed through A, B is auxiliary matrix)
        M_in  = A;
        M_out = B;

        // Iterate over timesteps
        for(int t = 0; t < iterations; ++t) {

            // Iterate over third dimension
            for(int k = 0; k < p; ++k) {

                // Double buffering: first DMA transaction
                if(core_idx == 8) {

                    issue_timer = pulp_get_timer();

                    // Fill first row over m dimension with 0 (for all k = 0,1,2)
                    dma_start_2d_wideptr(&l1_buf[0][1][1][1], idx(M_in, m, n, p, 0, 0, k), n*sizeof(DTYPE), BUF_SIZE*sizeof(DTYPE), n*sizeof(DTYPE), CORES+1);
                    // zero-pad borders
                    dma_start_1d_wideptr(l1_buf[0][1][0], ZERO_MEM, BUF_SIZE*sizeof(DTYPE));
                    for(int c = 0; c <= CORES; ++c) {
                        l1_buf[0][1][1+c][  0] = 0;
                        l1_buf[0][1][1+c][n+1] = 0;
                    }
                    
                    if (k > 0) {
                        dma_start_2d_wideptr(&l1_buf[0][0][1][1], idx(M_in, m, n, p, 0, 0, k-1), n*sizeof(DTYPE), BUF_SIZE*sizeof(DTYPE), n*sizeof(DTYPE), CORES+1);
                        // zero-pad borders
                        dma_start_1d_wideptr(l1_buf[0][0][0], ZERO_MEM, BUF_SIZE*sizeof(DTYPE));
                        for(int c = 0; c <= CORES; ++c) {
                            l1_buf[0][0][1+c][  0] = 0;
                            l1_buf[0][0][1+c][n+1] = 0;
                        }
                    } else {
                        // zero-pad entire channel
                        dma_start_1d_wideptr(l1_buf[0][0], ZERO_MEM, (CORES+2)*BUF_SIZE*sizeof(DTYPE));
                    }
                    
                    if (k < p - 1) {
                        dma_start_2d_wideptr(&l1_buf[0][2][1][1], idx(M_in, m, n, p, 0, 0, k+1), n*sizeof(DTYPE), BUF_SIZE*sizeof(DTYPE), n*sizeof(DTYPE), CORES+1);
                        // zero-pad borders
                        dma_start_1d_wideptr(l1_buf[0][2][0], ZERO_MEM, BUF_SIZE*sizeof(DTYPE));
                        for(int c = 0; c <= CORES; ++c) {
                            l1_buf[0][2][1+c][  0] = 0;
                            l1_buf[0][2][1+c][n+1] = 0;
                        }
                    } else {
                        // zero-pad entire channel
                        dma_start_1d_wideptr(l1_buf[0][2], ZERO_MEM, (CORES+2)*BUF_SIZE*sizeof(DTYPE));
                    }

                    issue_time += pulp_get_timer() - issue_timer;

                }

                int itr          = 0;
                int rows_covered = CORES;

                for(int i = 0; i < m; i += CORES) {
                    

                    if(core_idx == 8) {
                        
                        dma_timer = pulp_get_timer();
                        dma_wait_all();
                        dma_time += pulp_get_timer() - dma_timer;
                        
                        // Data is ready
                        pulp_barrier();

                        if(rows_covered < m) {

                            const int next_row  = rows_covered - 1;
                            const int rows_left = m - rows_covered;
                            int rows_to_copy = CORES + 2;
                            int rows_to_pad = 0;
                            if(rows_left <= CORES){
                                rows_to_copy = rows_left + 1;
                                rows_to_pad  = (CORES - rows_left) + 1;
                            }

                            issue_timer = pulp_get_timer();

                            // Not padding columns, as already padded at the beginning
                            dma_start_2d_wideptr(&l1_buf[(itr+1)%2][1][0][1], idx(M_in, m, n, p, next_row, 0, k), n*sizeof(DTYPE), BUF_SIZE*sizeof(DTYPE), n*sizeof(DTYPE), rows_to_copy);
                            
                            if(rows_to_pad > 0){
                                // Zero-pad remaining rows
                                dma_start_1d_wideptr(l1_buf[(itr+1)%2][1][rows_to_copy], ZERO_MEM, rows_to_pad*BUF_SIZE*sizeof(DTYPE));
                            }

                            if(k > 0) {
                                // Not padding columns, as already padded at the beginning
                                dma_start_2d_wideptr(&l1_buf[(itr+1)%2][0][0][1], idx(M_in, m, n, p, next_row, 0, k-1), n*sizeof(DTYPE), BUF_SIZE*sizeof(DTYPE), n*sizeof(DTYPE), rows_to_copy);
                                if(rows_to_pad > 0){
                                    // Zero-pad remaining rows
                                    dma_start_1d_wideptr(l1_buf[(itr+1)%2][0][rows_to_copy], ZERO_MEM, rows_to_pad*BUF_SIZE*sizeof(DTYPE));
                                }
                            } else {
                                // zero-pad entire channel
                                dma_start_1d_wideptr(l1_buf[(itr+1)%2][0], ZERO_MEM, (CORES+2)*BUF_SIZE*sizeof(DTYPE));
                            }
                            
                            if(k < p - 1){
                                // Not padding columns, as already padded at the beginning
                                dma_start_2d_wideptr(&l1_buf[(itr+1)%2][2][0][1], idx(M_in, m, n, p, next_row, 0, k+1), n*sizeof(DTYPE), BUF_SIZE*sizeof(DTYPE), n*sizeof(DTYPE), rows_to_copy);
                                if(rows_to_pad > 0){
                                    // Zero-pad remaining rows
                                    dma_start_1d_wideptr(l1_buf[(itr+1)%2][2][rows_to_copy], ZERO_MEM, rows_to_pad*BUF_SIZE*sizeof(DTYPE));
                                }
                            } else {
                                // zero-pad entire channel
                                dma_start_1d_wideptr(l1_buf[(itr+1)%2][2], ZERO_MEM, (CORES+2)*BUF_SIZE*sizeof(DTYPE));
                            }

                            issue_time += pulp_get_timer() - issue_timer;
                        }
                    }

                    if(core_idx < 8) {
                        // Wait for data to be ready
                        pulp_barrier();

                        asm volatile ("fence");

                        if(core_idx == 0) compute_timer = pulp_get_timer();
                        // Iterate over each element in row
                        for(int j = 0; j < n; ++j) {
                            DTYPE prev = l1_buf[itr%2][1][1+core_idx][1+j];
                            DTYPE delta = 0;
                            delta += l1_buf[itr%2][1][1+core_idx][  j] + l1_buf[itr%2][1][1+core_idx][2+j] - 2*prev;
                            delta += l1_buf[itr%2][1][  core_idx][1+j] + l1_buf[itr%2][1][2+core_idx][1+j] - 2*prev;
                            delta += l1_buf[itr%2][0][1+core_idx][1+j] + l1_buf[itr%2][2][1+core_idx][1+j] - 2*prev;
                            l1_res[core_idx][j] = prev + alpha * delta;
                        }

                        asm volatile ("fence");
                    }

                    pulp_barrier();

                    if(core_idx == 0) compute_time += pulp_get_timer() - compute_timer;

                    if(core_idx == 8) {
                        issue_timer = pulp_get_timer();
                        for (int c = 0; c < MIN(CORES, m - i); ++c){
                            dma_start_1d_wideptr(idx(M_out, m, n, p, i+c, 0, k), l1_res[c], n*sizeof(DTYPE));
                        }
                        issue_time += pulp_get_timer() - issue_timer;
                    }

                    rows_covered += CORES;
                    itr++;
                }
            
            }

            pulp_barrier();

            // Invert buffers
            uint32_t tmp;
            tmp   = M_in;
            M_in  = M_out;
            M_out = tmp;

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
