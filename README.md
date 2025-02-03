# HeroSDK

HeroSDK is an open-research software development kit for heterogeneous RISC-V platforms. This project enables deploying accelerated Linux user space applications using OpenMP target for programmable multi-core clusters. We currently target the open-source [Carfield](https://github.com/pulp-platform/carfield/) and [Occamy](https://github.com/pulp-platform/occamy/) platforms.

__HeroSDK is a continuity of Hero and HeroV2 but both projects are not yet compatible. Use the [original Hero repository](https://github.com/pulp-platform/hero) for everything referred to [HeroV2](https://arxiv.org/abs/2201.03861).__

HeroSDK is developed as part of the [PULP project](https://pulp-platform.org/), a joint effort between ETH Zurich and the University of Bologna.

The HeroSDK contains compilers (riscv64-linux-gcc & riscv64/32-linux/elf-clang), Linux kernel modules, host and device runtimes. See the figure below:

![image](https://pulp-platform.github.io/hero-tools/img/hero_sdk_stack.png)

## This repository

First, fetch the required repositories:

```bash
git submodule update --init --recursive
```

This repository contains the following directories:

| Directory    | Contains                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------ |
| `apps`       | Some example applications using OpenMP                                                           |
| `artifacts`  | Automatically managed artifact cache                                                             |
| `cva6-sdk`   | The cva6-sdk git submodule containing Buildroot                                                  |
| `docs`       | Files used to build the documentation                                                            |
| `install`*   | LLVM and compiled binaries and libraries. Also contains device's compiled newlibs.               |
| `output`*    | Intermediary compilation folder for LLVM and newlibs.                                            |
| `platforms`* | The hardware platforms available (cloned on demand)                                              |
| `scripts`    | Helper scripts                                                                                   |
| `sw`         | Hero runtime library, LLVM libraries, the OpenMP target runtime library, and the device drivers  |
| `toolchain`  | An LLVM fork containing the Hero OpenMP target runtime library implementation                    |
_* generated files_

## Example usage

Find below an example usage with Carfield taken from `apps/omp/basic/axpy`:

```C
/* axpy_snitch.c */

//////////////////////////////////
// Compiled for Host and Device //
//////////////////////////////////

#include <inttypes.h>

void dev_axpy(uint64_t x_phys, uint64_t y_phys, float alpha, uint32_t n);


int axpy(uint64_t x_phys, uint64_t y_phys, float alpha, uint32_t n) {
    #pragma omp target device(1) map(to:x_phys, y_phys, alpha, n)
    {
        // Important! Avoid LLVM to optimize shared arguments
        (volatile uint64_t) x_phys;
        (volatile uint64_t) y_phys;
        (volatile float) alpha;
        (volatile uint32_t) n;
        // Do not enter here if running on the Host
#ifdef __HERO_DEV
        dev_axpy(x_phys, y_phys, alpha, n);
#endif
    }

}

//////////////////////////////
// Device Kernel            //
//////////////////////////////

// Compile only for device
#ifdef __HERO_DEV

#define NUM_CORES 8
#define BUF_SIZE 64

#pragma omp declare target

// Double buffered compute buffers for Snitch cores
__device float l1_buf_x  [2][NUM_CORES][BUF_SIZE] __attribute__((section(".noinit_l1")));
__device float l1_buf_y  [2][NUM_CORES][BUF_SIZE] __attribute__((section(".noinit_l1")));

void dev_axpy(uint64_t x_phys, uint64_t y_phys, float alpha, uint32_t n) {

    const uint32_t core_idx = pulp_get_core_id();

    // Code for DMA core
    if(core_idx == 8) {
        issue_timer = pulp_get_timer();
        __dma_start_1d_wideptr_base((uint64_t) l1_buf_x[0], (uint64_t) x_phys, 8*BUF_SIZE*sizeof(float), 0);
        __dma_start_1d_wideptr_base((uint64_t) l1_buf_y[0], (uint64_t) y_phys, 8*BUF_SIZE*sizeof(float), 0);
        issue_time += pulp_get_timer() - issue_timer;
    }

    ...

    // Don't accumulate in first iteration
    asm volatile("mv t0, zero\n"
         // Don't accumulate in first iteration
         "addi t0, t0, 1\n\r"
         "flw ft1, 0(%[a]) \n"
         "add %[a], %[a], 4 \n"
         "flw ft2, 0(%[b]) \n"
         "fmadd.s ft2, %[alpha], ft1, ft2 \n"
         "fsw ft2, 0(%[b]) \n"
         "add %[b], %[b], 4 \n"
         "blt   t0, %[n], -28 \n"
         :
         : [n] "r"(BUF_SIZE), [a] "r"(&l1_buf_x[itr%2][core_idx]), [b] "r"(&l1_buf_y[itr%2][core_idx]), [alpha] "f"(alpha)
         : "ft1", "ft2", "t0");
        }

    ...

}

#pragma omp end declare target

#endif // __HERO_DEV

```

## Getting started

To build the software stack, compile a FPGA bitstream, get a Linux image, and more, go to [Getting Started](https://pulp-platform.github.io/hero-tools/gs/).

## Submodules

This project contains the following submodules:

- [CVA6-sdk](https://github.com/pulp-platform/cva6-sdk/) to build Linux images using [Buildroot](https://buildroot.org/).
- [llvm-project](https://github.com/llvm/llvm-project) to build the heterogeneous compiler and OpenMP target runtime.
- [o1heap](https://github.com/pavel-kirienko/o1heap) to manage dynamic memory allocation for device.

## License

Unless specified otherwise in the respective file headers, all code checked into this repository is made available under a permissive license. All software sources are licensed under Apache 2.0.

## References

C. Koenig, B. Forsberg, L. Benini: <ins>HeroSDK: Streamlining Heterogeneous RISC-V Accelerated Computing from Embedded to High-Performance Systems</ins>

A. Kurth, B. Forsberg, L. Benini: <ins>HEROv2: Full-Stack Open-Source Research Platform for Heterogeneous Computing</ins>
