// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

#pragma once

#include <stdlib.h>

extern int global_seed;

void init_omp_target();

inline int fast_rand() {
    global_seed = (214013*global_seed+2531011);
    return (global_seed>>16)&0x7FFF;
}
