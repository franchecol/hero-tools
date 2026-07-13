# H5: Reusable Multi-Job Runtime

H5 reuses the H4 job ABI for three submissions from one ARM Linux process.
The FPGA is programmed once, the IRQ driver is loaded once, the MMIO windows
are mapped once, and the RISC-V worker is uploaded once. Only the descriptor
and input/output data change between jobs.

```text
One board setup
  ├─ program the H3 FPGA image once
  ├─ load /dev/snitch_lite_irq once
  ├─ start one ARM host process
  ├─ map control/boot/shared memory once
  └─ upload the H4 RISC-V worker once
         │
         ├─ job 0 ─► IRQ event 1 ─► verify ─┐
         ├─ job 1 ─► IRQ event 2 ─► verify ─┼─ same process and payload
         └─ job 2 ─► IRQ event 3 ─► verify ─┘
```

H5 still resets and restarts Snitch for each job. The important advance over
H4 is that reset does not erase the host-loaded boot M10K, so the worker does
not need to be uploaded again.

## What Changed From H4

```text
H4                                      H5
────────────────────────────────────────────────────────────────────────
One descriptor submission               Three descriptor submissions
One interrupt event                     Monotonic events 1, 2, and 3
One fixed demonstration descriptor      Different count/multiplier/bias
Process exits after first result         Mapping and descriptors are reused
Payload uploaded for the invocation      Payload uploaded once for all jobs
```

No H5 RTL or new FPGA compilation is required. H5 reuses:

- H3 boot and shared M10K memories.
- H1's level-high FPGA-to-HPS interrupt and Linux driver.
- H4's descriptor ABI and descriptor-aware RISC-V worker.
- The upstream-derived one-core Snitch cluster fitted in U5/H0.

## Relaunch Protocol

[`sw/h5_host_nolibc.c`](sw/h5_host_nolibc.c) performs this sequence for each
job after the one-time setup:

```text
1. Hold Snitch in reset.
2. Wait until STATUS.result_valid is zero.
3. Write a new READY descriptor and input array.
4. Clear any stale IRQ pending bit.
5. Release Snitch from reset.
6. Poll the same IRQ file descriptor.
7. Read and verify the next monotonic event count.
8. Check completion 0x4834.
9. Reassert reset and wait for result_valid to clear.
10. Validate DONE/OK and every output word.
```

Step 2 is necessary because the interrupt latch detects the rising edge of
`result_valid`. Restarting before reset has propagated and cleared that signal
would not create a new edge. The wait also guarantees that shared-memory
ownership has returned to ARM before it writes the next descriptor.

## Test Jobs

All jobs run the same RISC-V operation:

```text
output[i] = input[i] * multiplier + bias
```

```text
Job  Inputs                       Multiplier  Bias  Expected outputs
0    2, 4, 8                     2           1     5, 9, 17
1    1, 3, 7, 16, 256, 1024     5           11    16, 26, 46, 91, 1291, 5131
2    0, 10, 100, 1000, 65536    7           3     3, 73, 703, 7003, 458755
```

The changing count proves this is not merely rereading one stale descriptor.
The monotonic kernel event count and different last outputs provide additional
evidence that all three Snitch executions completed independently.

## Reproduce

Build the H4 worker and H5 ARM host locally:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/h5_reusable_job_runtime
./scripts/test_build.sh
```

Run the physical test with Linux booted and both board USB cables attached:

```bash
BOARD_SUDO_PASSWORD=temppwd ./scripts/run_board_test.sh
```

The board script performs the one-time FPGA programming and driver loading.
The three submissions occur inside one execution of `h5_host_nolibc`; the
script does not invoke the host program three times.

## Physical Result

Verified on the DE1-SoC LXDE Linux image on 2026-07-13:

```text
H5_PAYLOAD_UPLOADS=0x00000001
JOB0_IRQ_EVENT=0x00000001
JOB0_STATE=0x00000003
JOB0_LAST_OUTPUT=0x00000011
H5_JOB0_PASS
JOB1_IRQ_EVENT=0x00000002
JOB1_STATE=0x00000003
JOB1_LAST_OUTPUT=0x0000140b
H5_JOB1_PASS
JOB2_IRQ_EVENT=0x00000003
JOB2_STATE=0x00000003
JOB2_LAST_OUTPUT=0x00070003
H5_JOB2_PASS
H5_REUSABLE_RUNTIME_PASS
```

## Bring-Up Finding

The larger H5 host initially failed its no-libc link because Clang inserted
stack-canary references. A freestanding `-nostdlib` executable has no libc
implementation of `__stack_chk_fail`, so the host build explicitly uses
`-fno-stack-protector`. This is a build-contract correction, not a board or
Snitch failure.

## Current Limitations

- The three jobs are compiled into the ARM executable.
- Snitch is reset and restarted for each job rather than waiting resident.
- User space still needs privileged `/dev/mem` access.
- The IRQ driver exposes completion events but not job submission or memory.
- There is one process and one in-flight job; no queue or concurrency exists.

The next logical milestone is H6: move MMIO and shared-memory ownership into a
single Linux job driver so an unprivileged user program no longer uses
`/dev/mem` directly.
