#pragma once

// soc_ctrl
#define CARFIELD_SAFETY_ISLAND_RST_OFFSET 0x28
#define CARFIELD_SAFETY_ISLAND_ISOLATE_OFFSET 0x40
#define CARFIELD_SAFETY_ISLAND_ISOLATE_STATUS_OFFSET 0x58
#define CARFIELD_SAFETY_ISLAND_CLK_EN_OFFSET 0x70
#define CARFIELD_SAFETY_ISLAND_BOOT_ADDR_OFFSET 0xcc
#define CARFIELD_SAFETY_ISLAND_FETCH_ENABLE_OFFSET 0xb8
#define CARFIELD_SPATZ_CLUSTER_RST_OFFSET 0x34
#define CARFIELD_SPATZ_CLUSTER_ISOLATE_OFFSET 0x4c
#define CARFIELD_SPATZ_CLUSTER_ISOLATE_STATUS_OFFSET 0x64
#define CARFIELD_SPATZ_CLUSTER_CLK_EN_OFFSET 0x7c
#define CARFIELD_SPATZ_CLUSTER_BOOT_ADDR_OFFSET 0xd8
#define CARFIELD_SPATZ_CLUSTER_BUSY_OFFSET 0xe8

// spatz-peripherals
#define CARFIELD_SNITCH_CLUSTER_BOOTADR_REG_OFFSET (0x0)
#define CARFIELD_SNITCH_CLUSTER_SCRATCH_REG_OFFSET (0x4)
#define CARFIELD_SNITCH_CLUSTER_PERIPHERAL_OFFSET 0x20000
#define CARFIELD_SNITCH_CLUSTER_CLINT_OFFSET (CARFIELD_SNITCH_CLUSTER_PERIPHERAL_OFFSET + 0x180)

// mboxes

// The virtual addresses of the hardware
volatile void* car_soc_ctrl;
volatile void* chs_ctrl_regs;
volatile void* car_mboxes;
volatile void* chs_idma;
volatile void* car_safety_island;
volatile void* car_spatz_cluster;
volatile void* car_l2_intl_0;
volatile void* car_l2_cont_0;
volatile void* car_l2_intl_1;
volatile void* car_l2_cont_1;
volatile void* car_l3;

