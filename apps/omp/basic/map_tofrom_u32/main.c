// Copyright 2026
// SPDX-License-Identifier: Apache-2.0
//
// Minimal HeroSDK/OpenMP correctness probe for FPGA bring-up.

#include <stdint.h>

#ifndef __HERO_1
#include <omp.h>
#include <stdio.h>
#endif

#include <hero_64.h>

int main(void) {
    uint32_t tmp_1 = 5;
    uint32_t tmp_2 = 10;

#pragma omp target device(1) map(tofrom : tmp_1, tmp_2)
    { tmp_1 = tmp_2; }

#ifndef __HERO_1
    if (tmp_1 != tmp_2) {
        printf("FAIL map_tofrom_u32: expected %u, got %u\n", tmp_2, tmp_1);
        return 1;
    }

    printf("PASS map_tofrom_u32: tmp_1=%u tmp_2=%u\n", tmp_1, tmp_2);
#endif

    return 0;
}
