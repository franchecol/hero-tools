// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Cyril Koenig <cykoenig@iis.ee.ethz.ch>

#pragma once

#define DTYPE float

#define MIN(A, B) (A < B ? A : B)
#define BUF_SIZE (512)

#ifdef __HERO_DEV

#ifdef __HERO_SNITCH_CLUSTER
#include "encoding.h"
#include "runtime.h"
#include "/usr/scratch2/wuerzburg/cykoenig/development/hero-tools/platforms/carfield/sw/tests/bare-metal/snitchd/common/printf.h"
#include "kernels/fdotp.h"
#define CORES 8
#define PREFETCHING 1
#endif

#endif // __HERO_DEV


#pragma omp declare target

__device DTYPE l1_buf_1  [8][2*BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_buf_2  [8][2*BUF_SIZE] __attribute__((section(".noinit_l1")));
__device DTYPE l1_buf_out[8][2*BUF_SIZE] __attribute__((section(".noinit_l1")));
__device uint32_t buf_1_head  [8]  __attribute__((section(".noinit_l1")));
__device uint32_t buf_1_tail  [8]  __attribute__((section(".noinit_l1")));
__device uint32_t buf_2_head  [8]  __attribute__((section(".noinit_l1")));
__device uint32_t buf_2_tail  [8]  __attribute__((section(".noinit_l1")));
__device uint32_t buf_1_off   [8]  __attribute__((section(".noinit_l1")));
__device uint32_t buf_2_off   [8]  __attribute__((section(".noinit_l1")));
__device uint64_t buf_1_addr  [8]  __attribute__((section(".noinit_l1")));
__device uint64_t buf_2_addr  [8]  __attribute__((section(".noinit_l1")));
__device uint64_t buf_out_addr[8]  __attribute__((section(".noinit_l1")));

__attribute__((section(".noinit_l1"))) volatile uint32_t dma_timer = 0, dma_time = 0, all_timer = 0, all_time = 0, issue_timer = 0, issue_time = 0, compute_timer = 0, compute_time = 0;

#ifdef __HERO_DEV

#define DMA_WAIT_ALL \
do { \
asm volatile ("fence"); \
dma_timer = pulp_get_timer(); \
dma_wait_all(); \
dma_time += pulp_get_timer() - dma_timer; \
asm volatile ("fence"); \
} while (0);

uint32_t dma_fill_buf(DTYPE *buf_l1, uint32_t buf_l1_size, uint32_t head, uint32_t tail, uint32_t off, uint64_t buf_l3_addr, uint32_t l3_elems_left, uint32_t core) {
    // Note that each transfer here is maximum of size BUF_SIZE (since the compute cores only process BUF_SIZE elements each)
    uint32_t tx_size = (tail <= head) ? head - tail : 2*buf_l1_size - tail + head;
    if(tx_size > l3_elems_left)
        tx_size = l3_elems_left;
    if(tx_size == 0)
        return 0;
    issue_timer = pulp_get_timer();
    if(tail > head) {
        uint32_t tx_1_size = 2*buf_l1_size - tail;
        // First transfer from tail to the end of the buffer
        __dma_start_1d_wideptr_base((uint64_t) &buf_l1[tail], buf_l3_addr + off*sizeof(DTYPE), tx_1_size*sizeof(DTYPE), 0);
        // Second transfer from start of the buffer to tail
        if(tx_1_size != tx_size)
            __dma_start_1d_wideptr_base((uint64_t) &buf_l1[0], buf_l3_addr + off*sizeof(DTYPE) + tx_1_size*sizeof(DTYPE), (tx_size-tx_1_size)*sizeof(DTYPE), 0);
    } else if (tail < head) {
        // One transfer from head to tail
        __dma_start_1d_wideptr_base((uint64_t) &buf_l1[tail], buf_l3_addr + off*sizeof(DTYPE), tx_size*sizeof(DTYPE), 0);
    }
    issue_time += pulp_get_timer() - issue_timer;
    return tx_size;
}

static inline void simple_l1_merge(DTYPE *buf_1, DTYPE *buf_2, DTYPE *buf_out, int bufs_size) {
    int buf_1_off = 0;
    int buf_2_off = 0;
    for(int k = 0; k < 2*bufs_size; k++) {
        if((buf_1_off != bufs_size) && (buf_2_off == bufs_size || buf_1[buf_1_off] <= buf_2[buf_2_off])) {
            buf_out[k] = buf_1[buf_1_off++];
        } else {
            buf_out[k] = buf_2[buf_2_off++];
        }
    }
}

static inline void merge_bufs(uint64_t buf_1_addr[8], uint64_t buf_2_addr[8], uint64_t buf_out_addr[8], uint64_t l3_buf_size) {
    uint32_t core_idx     = pulp_get_core_id();

    // If l3_buf_size is smaller than BUF_SIZE, limit the working size
    uint32_t buf_size = l3_buf_size < BUF_SIZE ? l3_buf_size : BUF_SIZE;

    // Local copies used by the compute core
    uint32_t next_buf_1_head = 0;
    uint32_t next_buf_2_head = 0;
    uint32_t buf_1_size = l3_buf_size;
    uint32_t buf_2_size = l3_buf_size;

    // Only wait in (issue with dma out...)
    dma_txid_t wait_id = 0;

    if(core_idx < 8) {
        // Global pointers used by the DMA core
        buf_1_head[core_idx] = 0;
        buf_1_tail[core_idx] = buf_size;
        buf_2_head[core_idx] = 0;
        buf_2_tail[core_idx] = buf_size;
        // offset in l3 buffer
        buf_1_off[core_idx] = buf_size;
        buf_2_off[core_idx] = buf_size;
    } else if (core_idx == 8) {
        issue_timer = pulp_get_timer();
        for(int core = 0; core < 8; core++) {
            //if(core == 0)
            //        printf("%x -> %x -> %x (%x)\n\r", (uint32_t)(buf_1_addr[core]), &l1_buf_1[core][0], buf_size);
            if(buf_1_addr[core] == 0)
                continue;
            __dma_start_1d_wideptr_base((uint64_t) &l1_buf_1[core][0], buf_1_addr[core], buf_size*sizeof(DTYPE), 0);
            __dma_start_1d_wideptr_base((uint64_t) &l1_buf_2[core][0], buf_2_addr[core], buf_size*sizeof(DTYPE), 0);
        }
        issue_time += pulp_get_timer() - issue_timer;
    }


    for(int elems_out = 0; elems_out < 2*l3_buf_size; elems_out += buf_size) {

        // Issue DMA to re-fill the L1 buffers for next iteration
        if(core_idx == 8) {

            asm volatile ("fence");
            dma_timer = pulp_get_timer();
            #if PREFETCHING
            //volatile uint8_t prefetching;
            //if(buf_1_addr[0] != 0) {
            //prefetching = *(uint8_t*)(buf_1_addr[0] + buf_1_off[0]*sizeof(DTYPE));
            //prefetching = *(uint8_t*)(buf_2_addr[0] + buf_2_off[0]*sizeof(DTYPE));
            //prefetching = *(uint8_t*)(buf_2_addr[0] + buf_2_off[0]*sizeof(DTYPE));
            //}
            #endif
            dma_wait_all();
            dma_time += pulp_get_timer() - dma_timer;
            asm volatile ("fence");

            // Make sure DMA is over, but also that heads and tails are updated
            pulp_barrier();

            for(int core = 0; core < 8; core++) {
                // We might not need to work in the last steps of the algorithm
                if(buf_1_addr[core] == 0)
                    continue;
                // Fetch next buffers
                buf_1_off[core] += dma_fill_buf(&l1_buf_1[core][0], buf_size, buf_1_head[core], buf_1_tail[core], buf_1_off[core], buf_1_addr[core], l3_buf_size-buf_1_off[core], core);
                buf_2_off[core] += dma_fill_buf(&l1_buf_2[core][0], buf_size, buf_2_head[core], buf_2_tail[core], buf_2_off[core], buf_2_addr[core], l3_buf_size-buf_2_off[core], core);

            }
        }

        // Compare L1 buffers (only what have been filled from last iteration) and fill output buffer
        if(core_idx < 8) {
            // Synch with after the dma wait all
            if(core_idx == 0)
                compute_timer = pulp_get_timer();
            pulp_barrier();
            if(buf_1_addr[core_idx] != 0) {
                for(int k = 0; k < buf_size; k++) {
                    // Make sure we decrease the buffer size
                    if((!buf_2_size || l1_buf_1[core_idx][next_buf_1_head] <= l1_buf_2[core_idx][next_buf_2_head]) && buf_1_size) {
                        l1_buf_out[core_idx][k] = l1_buf_1[core_idx][next_buf_1_head];
                        next_buf_1_head = (next_buf_1_head+1) % (2*buf_size);
                        buf_1_size--;
                    } else if (buf_2_size) {
                        l1_buf_out[core_idx][k] = l1_buf_2[core_idx][next_buf_2_head];
                        next_buf_2_head = (next_buf_2_head+1) % (2*buf_size);
                        buf_2_size--;
                    }
                }
            }
        }

        pulp_barrier();

        if(core_idx == 0)
            compute_time += pulp_get_timer() - compute_timer;

        // Now that dma have been issued we can update heads and tails
        if(core_idx < 8 && buf_1_addr[core_idx] != 0) {
            buf_1_tail[core_idx] = buf_1_head[core_idx];
            buf_2_tail[core_idx] = buf_2_head[core_idx];
            buf_1_head[core_idx] = next_buf_1_head;
            buf_2_head[core_idx] = next_buf_2_head;
        }

        // Send back result
        if(core_idx == 8) {
            for(int core = 0; core < 8; core++) {
                if(buf_1_addr[core] == 0)
                    continue;

                asm volatile ("fence");
                dma_timer = pulp_get_timer();
                #if PREFETCHING
                // Note this is contiguous
                //volatile uint8_t prefetching;
                //if(core > 0 && buf_size > 128) {
                //    prefetching = *(uint8_t*)(buf_out_addr[core] + (elems_out)*sizeof(DTYPE));
                //}
                #endif
                dma_wait_all();
                dma_time += pulp_get_timer() - dma_timer;
                asm volatile ("fence");

                // For some reason outbound request can not be parallel (todo replace with 2d tranfert)

                __dma_start_1d_wideptr_base(buf_out_addr[core] + (elems_out)*sizeof(DTYPE), (uint64_t) &l1_buf_out[core][0], buf_size*sizeof(DTYPE), 0);
            }
        }
    }
}


#endif // __HERO_DEV
#pragma omp end declare target

int merge_sort(DTYPE *xin_, uint32_t xin_p_, DTYPE *xout_, uint32_t xout_p_, int n_)
{

#pragma omp target device(1) map(to : n_, xout_p_, xin_p_)
    {
        // Avoid argument optimization
        volatile uint32_t n__      = n_;
        volatile uint32_t xout_p__ = xout_p_;
        volatile uint32_t xin_p__  = xin_p_;

        // Device kernel
#ifdef __HERO_DEV

        const uint32_t n        = n_;
        const uint32_t xout_p   = xout_p_;
        const uint32_t xin_p   = xin_p_;
        const uint32_t core_idx = pulp_get_core_id();

        dma_time = 0;
        all_time = 0;
        compute_time = 0;
        issue_time = 0;

        if (!n || !xout_p || !xin_p ) {
            goto omp_exit;
        }

        uint32_t global_itr = 0;
        uint32_t log_counter = n / 8;
        uint32_t itr_counter = 1;

        // Only power of two works
        if((log_counter & (log_counter - 1)) != 0 && log_counter != 0)
            goto omp_exit;

        if(core_idx == 8)
            all_timer = pulp_get_timer();

        while(log_counter > 1) {
            // If we don't need double buffering to merge two buffers
            if(itr_counter <= BUF_SIZE) {
                for(int I = 0; I < n; I += BUF_SIZE*2*8) {
                    int len = MIN(BUF_SIZE*2*8, n);
                    if(core_idx == 8) {
                        // printf("%u core_idx %u %x %u %u\n\r", core_idx, xin_p + (global_itr%2)*n*sizeof(DTYPE) + I*sizeof(DTYPE), I, len);
                        issue_timer = pulp_get_timer();
                        __dma_start_1d_wideptr_base(l1_buf_1, xin_p + (global_itr%2)*n*sizeof(DTYPE) + I*sizeof(DTYPE), len*sizeof(DTYPE), 0);
                        issue_time += pulp_get_timer() - issue_timer;
                        dma_timer = pulp_get_timer();
                        dma_wait_all();
                        dma_time += pulp_get_timer() - dma_timer;
                    }
                    pulp_barrier();
                    if(core_idx == 0)
                        compute_timer = pulp_get_timer();
                    for (int i = 0; i < len; i += (itr_counter*2*8)) {
                        if(i >= n)
                            break;
                        if(core_idx < 8) {
                            __device DTYPE* buf_1   = (__device DTYPE*) ((void *)l1_buf_1 + (i+core_idx*2*itr_counter)*sizeof(DTYPE));
                            __device DTYPE* buf_2   = (__device DTYPE*) ((void *)l1_buf_1 + (i+core_idx*2*itr_counter+itr_counter)*sizeof(DTYPE));
                            __device DTYPE* buf_out = (__device DTYPE*) ((void *)l1_buf_2 + (i+core_idx*2*itr_counter)*sizeof(DTYPE));
                            simple_l1_merge(buf_1, buf_2, buf_out, itr_counter);
                        }
                    }
                    pulp_barrier();
                    if(core_idx == 0)
                        compute_time += pulp_get_timer() - compute_timer;

                    if(core_idx == 8) {
                        // printf("%u core_idx %u %x %u %u\n\r", core_idx, xin_p + ((global_itr+1)%2)*n*sizeof(DTYPE) + I*sizeof(DTYPE), I, len);
                        issue_timer = pulp_get_timer();
                        __dma_start_1d_wideptr_base(xin_p + ((global_itr+1)%2)*n*sizeof(DTYPE) + I*sizeof(DTYPE), l1_buf_2, len*sizeof(DTYPE), 0);
                        issue_time += pulp_get_timer() - issue_timer;
                    }
                }
            // If we need double buffering to merge two buffers
            } else {
                for (int i = 0; i < n / 8; i += (itr_counter*2)) {
                    if(core_idx < 8) {
                        buf_1_addr[core_idx]   = xin_p + (global_itr%2)*n*sizeof(DTYPE)     + core_idx*(n/8)*sizeof(DTYPE) + i*sizeof(DTYPE);
                        buf_2_addr[core_idx]   = xin_p + (global_itr%2)*n*sizeof(DTYPE)     + core_idx*(n/8)*sizeof(DTYPE) + (i+itr_counter)*sizeof(DTYPE);
                        buf_out_addr[core_idx] = xin_p + ((global_itr+1)%2)*n*sizeof(DTYPE) + core_idx*(n/8)*sizeof(DTYPE) + i*sizeof(DTYPE);
                    }
                    pulp_barrier();
                    merge_bufs(buf_1_addr, buf_2_addr, buf_out_addr, itr_counter);
                    pulp_barrier();
                }
            }

            global_itr++;
            itr_counter = itr_counter << 1;
            log_counter = log_counter >> 1;
        }

        itr_counter = 2;
        while(itr_counter <= 8) {
            // Final merges (some cores don't work anymore)
            if(core_idx < 8 && (core_idx % itr_counter == 0)) {
                // asm volatile ("fence");
                // if(core_idx == 0)
                //     printf("\n\r%x [%u %u (%u)]\n\r\n\r", core_idx*(n/8), (core_idx + itr_counter/2)*(n/8), itr_counter/2*n/8);
                buf_1_addr[core_idx]   = xin_p + global_itr%2*n*sizeof(DTYPE)     + core_idx*(n/8)*sizeof(DTYPE);
                buf_2_addr[core_idx]   = xin_p + global_itr%2*n*sizeof(DTYPE)     + (core_idx + itr_counter/2)*(n/8)*sizeof(DTYPE);
                if(itr_counter == 8)
                    buf_out_addr[core_idx] = xout_p;
                else
                    buf_out_addr[core_idx] = xin_p + (global_itr+1)%2*n*sizeof(DTYPE) + core_idx*(n/8)*sizeof(DTYPE);
                // asm volatile ("fence");
            } else if (core_idx < 8) {
                // asm volatile ("fence");
                buf_1_addr[core_idx] = 0;
                buf_2_addr[core_idx] = 0;
                buf_out_addr[core_idx] = 0;
                // asm volatile ("fence");
            }
            pulp_barrier();
            merge_bufs(buf_1_addr, buf_2_addr, buf_out_addr, itr_counter/2*n/8);
            global_itr++;
            pulp_barrier();
            itr_counter = itr_counter * 2;
        }

    if(core_idx == 8) {
        all_time = pulp_get_timer() - all_timer;
        printf("%x Tot : %u Dma : %u Issue : %u Compute : %u\n\r", all_time, dma_time, issue_time, compute_time);
    }
omp_exit:
        ;
#endif
    }
}
