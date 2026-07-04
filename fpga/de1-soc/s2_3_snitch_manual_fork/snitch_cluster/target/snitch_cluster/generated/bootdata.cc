// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include <tb_lib.hh>

namespace sim {

const BootData BOOTDATA = {.boot_addr = 0x1000,
                           .core_count = 1,
                           .hartid_base = 0,
                           .tcdm_start = 0x10000000,
                           .tcdm_size = 0x4000,
                           .tcdm_offset = 0x0,
                           .global_mem_start = 0x80000000,
                           .global_mem_end = 0x100000000,
                           .cluster_count = 1,
                           .s1_quadrant_count = 1,
                           .clint_base = 0xffff0000};

}  // namespace sim
