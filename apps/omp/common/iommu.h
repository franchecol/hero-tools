// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig   <cykoenig@iis.ee.ethz.ch>
// Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

#pragma once

#define IOMMU_BASE           0x2000a000
#define IOMMU_EVNT_OFFSET_L  0x00000160
#define IOMMU_EVNT_OFFSET_H  0x00000164
#define IOMMU_CNTR_OFFSET_L  0x00000068
#define IOMMU_CNTR_OFFSET_H  0x0000006c
#define IOMMU_DUMP_OFFSET_L  0x00000400
#define IOMMU_DUMP_OFFSET_H  0x00000404
#define IOMMU_INDX_OFFSET    0x00000800

extern uint64_t iommu_devmap();

extern void iommu_enable();

extern void iommu_reset_counters(uint64_t iommu_base_virt);

extern void iommu_print_stats(uint64_t iommu_base_virt);
