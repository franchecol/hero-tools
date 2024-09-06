// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig <cykoenig@iis.ee.ethz.ch>

#pragma once

#include <inttypes.h>

// 32-bit dot-product: a * b
float fdotp_simd_32b(const float *a, const float *b, float *c, unsigned int K)
{
    const register float zero = 0.0;

    // Don't accumulate in first iteration
    asm volatile("vfcpka.s.s ft3, %[zero], %[zero]\n"
                 // Don't accumulate in first iteration
                 "fld ft1, 0(%[a]) \n"
                 "fld ft2, 0(%[b]) \n"
                 "add %[a], %[a], 8 \n"
                 "add %[b], %[b], 8 \n"
                 "vfmul.s ft4, ft1, ft2 \n"
                 // loop over the MACs
                 "li     t0, 2 \n"
                 "3: \n"
                 "fld ft1, 0(%[a]) \n"
                 "fld ft2, 0(%[b]) \n"
                 "vfmac.s ft4, ft1, ft2 \n"
                 "add %[a], %[a], 8 \n"
                 "add %[b], %[b], 8 \n"
                 "addi  t0, t0, 2 \n"
                 "blt   t0, %[K], 3b \n"
                 // Sum reduce vector
                 "vfsum.s ft3, ft4 \n"
                 // Store results
                 "fsw ft3, 0(%[c]) \n"
                 : [a] "+r"(a), [b] "+r"(b)
                 : [c] "r"(c), [K] "r"(K), [zero] "f"(zero)
                 : "ft0", "ft1", "ft2", "ft3", "ft4", "t0");
}

// 32-bit dot-product: a * b
float fdotp_rvv_32b(const float *a, const float *b, float *c, unsigned int avl)
{
#ifdef __HERO_SPATZ_CLUSTER
    const unsigned int orig_avl = avl;
    unsigned int vl;

    float red;

    // Stripmine and accumulate a partial reduced vector
    do {
        // Set the vl
        asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));

        // Load chunk a and b
        asm volatile("vle32.v v8,  (%0)" ::"r"(a));
        asm volatile("vle32.v v16, (%0)" ::"r"(b));

        // Multiply and accumulate
        if (avl == orig_avl) {
            asm volatile("vfmul.vv v24, v8, v16");
        } else {
            asm volatile("vfmacc.vv v24, v8, v16");
        }

        // Bump pointers
        a += vl;
        b += vl;
        avl -= vl;
    } while (avl > 0);

    // Reduce and return
    asm volatile("vmv.v.i v0, 0");
    asm volatile("vfredusum.vs v0, v24, v0");
    asm volatile("vfmv.f.s %0, v0" : "=f"(red));
    *c = red;
#endif
}

// 32-bit dot-product: a * b
PULP_NOINLINE float fdotp_naive_32b(const float *a, const float *b, float *c, unsigned int K)
{
    float value = 0;
    for (int i = 0; i < K; i++) {
        value += a[i] * b[i];
    }
    *c = value;
    return value;
}

// 64-bit dot-product: a * b
static inline double fdotp_naive_64b(const double *a, const double *b, double *c, unsigned int K)
{
    double value = 0;
    for (int i = 0; i < K; i++) {
        value += a[i] * b[i];
    }
    *c = value;
    return value;
}

// 32-bit dot-product: a * b
PULP_NOINLINE float fdotp_opti_32b(const float *a, const float *b, float *c, const unsigned int K)
{
    const register float zero = 0.0;

    // Don't accumulate in first iteration
    asm volatile("mv t0, zero\n"
                 "fmv.s ft3, %[zero]\n"
                 // Don't accumulate in first iteration
                 "addi t0, t0, 1\n\r"
                 "flw ft1, 0(%[a]) \n"
                 "add %[a], %[a], 4 \n"
                 "flw ft2, 0(%[b]) \n"
                 "add %[b], %[b], 4 \n"
                 "fmadd.s ft3, ft1, ft2, ft3 \n"
                 "blt   t0, %[K], -24 \n"
                 // Store results
                 "fsw ft3, 0(%[c]) \n"
                 : [a] "+r"(a), [b] "+r"(b)
                 : [c] "r"(c), [K] "r"(K), [zero] "f"(zero)
                 : "ft1", "ft2", "ft3", "t0");
}

// 32-bit dot-product: a * b
PULP_NOINLINE double fdotp_opti_64b(const double *a, const double *b, double *c, const unsigned int K)
{
    const register double zero = 0.0;

    // Don't accumulate in first iteration
    asm volatile("mv t0, zero\n"
                 "fmv.d ft3, %[zero]\n"
                 // Don't accumulate in first iteration
                 "addi t0, t0, 1\n\r"
                 "fld ft1, 0(%[a]) \n"
                 "add %[a], %[a], 8 \n"
                 "fld ft2, 0(%[b]) \n"
                 "add %[b], %[b], 8 \n"
                 "fmadd.d ft3, ft1, ft2, ft3 \n"
                 "blt   t0, %[K], -24 \n"
                 // Store results
                 "fsd ft3, 0(%[c]) \n"
                 : [a] "+r"(a), [b] "+r"(b)
                 : [c] "r"(c), [K] "r"(K), [zero] "f"(zero)
                 : "ft1", "ft2", "ft3", "t0");
}


PULP_NOINLINE double fdotp_ssr_64b(const double *a, const double *b, double *c, unsigned int K) {
    // Start of SSR region.
    //register volatile double ft0 asm("ft0");
    asm volatile("fcvt.d.w	ft5, zero");
    register volatile double ssr1 asm("ft1");
    register volatile double ssr2 asm("ft2");
    asm volatile("" : "=f"(ssr1));
    asm volatile("" : "=f"(ssr2));

    ssr_loop_1d(SSR_DM1, K, sizeof(double));
    ssr_loop_1d(SSR_DM2, K, sizeof(double));

    ssr_read(SSR_DM1, SSR_1D, a);
    ssr_read(SSR_DM2, SSR_1D, b);

    ssr_enable();

    for(int i = 0; i < K; i++) {
        asm volatile ("fadd.d ft5, ft1, ft2");
    }

    ssr_disable();
    asm volatile("" : : "f"(ssr1));
    asm volatile("" : : "f"(ssr2));
    asm volatile("fld ft4, 0(%0)" : : "r"(a));
    asm volatile("nop");asm volatile("nop");asm volatile("nop");asm volatile("nop");asm volatile("nop");asm volatile("nop");
    asm volatile("fsd ft4, 0(%0)" : : "r"(c));
}

PULP_NOINLINE float fdotp_ssr_32b(const float *a, const float *b, float *c, unsigned int K) {
    // Start of SSR region.
    //register volatile float ft0 asm("ft0");
    float result = 0;
    asm volatile("fcvt.s.w	ft5, zero");
    register volatile float ssr1 asm("ft1");
    register volatile float ssr2 asm("ft2");
    asm volatile("" : "=f"(ssr1));
    asm volatile("" : "=f"(ssr2));

    ssr_loop_1d(SSR_DM1, K, sizeof(float));
    ssr_loop_1d(SSR_DM2, K, sizeof(float));

    ssr_read(SSR_DM1, SSR_1D, a);
    ssr_read(SSR_DM2, SSR_1D, b);

    ssr_enable();

    for(int i = 0; i < K; i++) {
        asm volatile ("fmadd.s ft5, ft1, ft2, ft5");
    }

    ssr_disable();
    asm volatile("" : : "f"(ssr1));
    asm volatile("" : : "f"(ssr2));
    asm volatile("fsw ft5, 0(%[c])" :: [c] "r"(c));

    return 0;
}