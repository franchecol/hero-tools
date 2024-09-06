// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig <cykoenig@iis.ee.ethz.ch>

#pragma once

#define DTYPE float
#define fdotp fdotp_opti_32b

#define MIN(A, B) (A < B ? A : B)
#define MAX_ELEM (128 - 32) * 1024 / (sizeof(DTYPE))

#ifdef __HERO_DEV

#ifdef __HERO_SNITCH_CLUSTER
#include "encoding.h"
#include "runtime.h"
#include "/scratch2/cykoenig/development/hero-tools/platforms/carfield/sw/tests/bare-metal/snitchd/common/printf.h"
#include "kernels/fdotp.h"
#define CORES 8
#define BUF_SIZE (512)
#endif

#ifdef __HERO_OCCAMY
#include "encoding.h"
#include "inttypes.h"
#define CORES 8
#define hero_dma_1d_async dm_memcpy_async
#define hero_dma_wait_all dm_wait
#endif

#ifdef __HERO_SPATZ_CLUSTER
#include "kernels/fdotp.h"
#include "omp.h"
#include "printf.h"
#include "snrt.h"
#define CORES 2
#define hero_dma_1d_async snrt_dma_start_1d_wideptr
#define hero_dma_wait_all snrt_dma_wait_all
#endif

#endif // __HERO_DEV

#ifndef __HERO_SNITCH_CLUSTER

int matvec(DTYPE *xout_, uint32_t xout_p_, DTYPE *x_, uint32_t x_p_, DTYPE *w_, uint32_t w_p_, int n_, int d_)
{

    if (n_ * 9 > MAX_ELEM) {
        printf("Error : Size too large\n\r");
        return -1;
    }

    char toprint[128];
    snprintf(toprint, 128, "enter_omp_matvec-%u", n_);
    hero_add_timestamp(toprint, __func__, 0);

#pragma omp target device(1) map(to : n_, d_, xout_p_, x_p_, w_p_)
    {
        volatile uint32_t n      = n_;
        volatile uint32_t d      = d_;
        volatile uint32_t xout_p = xout_p_;
        volatile uint32_t x_p    = x_p_;
        volatile uint32_t w_p    = w_p_;

#ifdef __HERO_DEV

        if (!n || !d || !xout_p || !x_p || !w_p) {
            goto omp_exit;
        }

        // printf("%x - %x %x %x %x %x\n\r", (uint32_t)n, (uint32_t)d, (uint32_t)xout_p, (uint32_t)x_p,
        // (uint32_t)w_p);

        DTYPE *x_l1[2];
        x_l1[0] = (DTYPE *)snrt_l1alloc(n * sizeof(DTYPE));
        DTYPE *w_row_l1[2];
        w_row_l1[0] = (DTYPE *)snrt_l1alloc(2 * n * sizeof(DTYPE));
        w_row_l1[1] = (DTYPE *)snrt_l1alloc(2 * n * sizeof(DTYPE));

        hero_dma_1d_async((void *)x_l1[0], (const void *)x_p, n * sizeof(DTYPE));
        hero_dma_1d_async((void *)w_row_l1[0], (const void *)w_p, n * 2 * sizeof(DTYPE));

        int it      = 0;
        uint32_t t0 = 0, tot_dma = 0, tot_dotp = 0;

        for (int I = 0; I < d; I += CORES) {
            int rows_left = d - I;
            t0            = read_csr(mcycle);
            hero_dma_wait_all();
            tot_dma += read_csr(mcycle) - t0;
            if (rows_left > 2)
                hero_dma_1d_async(w_row_l1[(it + 1) % 2], w_p + n * sizeof(DTYPE) * (I + CORES),
                                  n * MIN(rows_left - CORES, CORES) * sizeof(DTYPE));

            t0 = read_csr(mcycle);
#pragma omp parallel for
            for (int i = 0; i < CORES; i++) {
                DTYPE val = 0.0f;
                if (I + i >= d)
                    goto end;
                fdotp_32b(x_l1[0], &(w_row_l1[it % 2][snrt_cluster_core_idx() * n]), &((DTYPE *)xout_p)[i + I], n);

            end:;
            }
            tot_dotp += read_csr(mcycle) - t0;
            it++;
        }
        // printf("%i %i %i\n\r", tot_dma, tot_dotp);

#endif

    omp_exit:;
    }
    hero_add_timestamp("enter_omp_end", __func__, 1);
    return 0;
}

#endif // __HERO_SNITCH_CLUSTER

#ifdef __HERO_SNITCH_CLUSTER

#ifdef __HERO_DEV
#endif

int matvec(DTYPE *xout_, uint32_t xout_p_, DTYPE *x_, uint32_t x_p_, DTYPE *w_, uint32_t w_p_, int n_, int d_)
{

    if (n_ * 9 > MAX_ELEM) {
        printf("Error : Size too large\n\r");
        return -1;
    }

    char toprint[128];
    snprintf(toprint, 128, "enter_omp_matvec-%u", n_);
    hero_add_timestamp(toprint, __func__, 0);

#pragma omp target device(1) map(to : n_, d_, xout_p_, x_p_, w_p_)
    {
        // Avoid argument optimization
        volatile uint32_t n__      = n_;
        volatile uint32_t d__      = d_;
        volatile uint32_t xout_p__ = xout_p_;
        volatile uint32_t x_p__    = x_p_;
        volatile uint32_t w_p__    = w_p_;

        // Device kernel
#ifdef __HERO_DEV

        const uint32_t n        = n_;
        const uint32_t d        = d_;
        const uint32_t xout_p   = xout_p_;
        const uint32_t x_p      = x_p_;
        const uint32_t w_p      = w_p_;
        const uint32_t core_idx = pulp_get_core_id();
        uint32_t dma_timer, dma_time = 0, timer, time = 0;

        if (!n || !d || !xout_p || !x_p || !w_p || n > BUF_SIZE) {
            goto omp_exit;
        }

        // Initialize allocator pointer in stack
        __device void * next_l1_alloc =  (__device void *) get_l1_alloc_base();
        __device uint32_t * const l1_lock_ptr = (__device uint32_t * ) l1_alloc(sizeof(uint32_t), next_l1_alloc);
        *l1_lock_ptr = 0;
        __device DTYPE * row_bufs[2];
        row_bufs[0] = (__device DTYPE * ) l1_alloc(BUF_SIZE * CORES * sizeof(DTYPE), next_l1_alloc);
        row_bufs[1] = (__device DTYPE * ) l1_alloc(BUF_SIZE * CORES * sizeof(DTYPE), next_l1_alloc);
        __device DTYPE * const vec_buf = (__device DTYPE * ) l1_alloc(BUF_SIZE * sizeof(DTYPE), next_l1_alloc);
        __device DTYPE * l1_output[2];
        l1_output[0]  = (__device DTYPE * ) l1_alloc(CORES * sizeof(DTYPE), next_l1_alloc);
        l1_output[1]  = (__device DTYPE * ) l1_alloc(CORES * sizeof(DTYPE), next_l1_alloc);

        if(core_idx == 8) {
            dma_start_1d_wideptr(row_bufs[0], w_p, n * CORES * sizeof(DTYPE));
            dma_start_1d_wideptr(vec_buf    , x_p, n * sizeof(DTYPE));
        }

        int itr = 0;
        for (int I = 0; I < d; I += CORES) {
            const int rows_left = d - I;
            if(core_idx == 8) {
                dma_timer = pulp_get_timer();
                dma_wait_all();
                dma_time += pulp_get_timer() - dma_timer;
                if(rows_left > CORES)
                    dma_start_1d_wideptr(row_bufs[(itr+1)%2], w_p + n * sizeof(DTYPE) * (I + CORES),
                                         n * MIN(rows_left - CORES, CORES) * sizeof(DTYPE));
            }
            timer = pulp_get_timer();
            pulp_barrier();
            if(core_idx < 8) {
                asm volatile ("fence");    
                fdotp(&vec_buf[0], &(row_bufs[itr % 2][core_idx * n]), &l1_output[itr%2][core_idx], n);
                asm volatile ("fence");
            }
            pulp_barrier();
            time += pulp_get_timer() - timer;
            if(core_idx == 8){
                dma_start_1d_wideptr(&((DTYPE *)xout_p)[I], l1_output[itr%2], CORES * sizeof(DTYPE));
            }
            itr++;
        }

        pulp_barrier();
        if(core_idx == 8){
            printf("%x %u %u\n\r", core_idx, dma_time);
        }
        pulp_barrier();
        if(core_idx == 0){
            printf("%x %u %u\n\r", core_idx, time);
        }

#endif

    omp_exit:;
    }
    return 0;
}

#endif // __HERO_SNITCH_CLUSTER
