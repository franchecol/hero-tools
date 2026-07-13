# H6: Unified Linux Snitch Job Driver

H6 moves FPGA control, boot-memory access, shared-memory access, reset
sequencing, and completion IRQ handling out of the ARM application and into
one Linux kernel module. A non-root client now uses `/dev/snitch_job` instead
of opening privileged `/dev/mem` and a separate IRQ device.

```text
ARM application, UID 1000
  │
  ├─ write(/dev/snitch_job, RISC-V worker)
  └─ ioctl(/dev/snitch_job, SUBMIT, job)
                         │
                         ▼
              snitch_job.ko kernel driver
                 ├─ validate FPGA capabilities
                 ├─ serialize one client/job
                 ├─ control Snitch reset
                 ├─ write boot and shared M10K
                 ├─ release Snitch
                 ├─ block on FPGA-to-HPS IRQ
                 ├─ reassert reset
                 └─ return status and outputs
```

H6 is a software integration milestone over the unchanged H3 FPGA image. No
new RTL, Quartus fit, or gate-level synthesis is required.

## What Changed From H5

```text
H5 application                       H6 application
──────────────────────────────────────────────────────────────────────
Runs with sudo                       Runs as ubuntu, UID 1000
Opens /dev/mem                       Never opens /dev/mem
Maps 0xff200000-0xff202fff           Has no physical-address knowledge
Opens separate IRQ device            Opens only /dev/snitch_job
Sequences reset and pending bits     Uses blocking SUBMIT ioctl
Writes H4 descriptor directly        Passes a typed h6_job structure
Validates FPGA capability registers  Driver validates at module load
```

The H6 application still controls which RISC-V program and data operation to
request. The kernel driver owns how that request reaches hardware safely.

## Userspace ABI

[`include/h6_job_api.h`](include/h6_job_api.h) is shared by the kernel module
and no-libc ARM client. Its fixed 288-byte structure contains:

```text
Input from application       Output from driver
────────────────────────────────────────────────────────────
count                        status
multiplier                   completion signature
bias                         monotonic IRQ event count
input[32]                    output[32]
```

The interface has two operations:

```c
write(fd, firmware, firmware_bytes);
ioctl(fd, H6_JOB_IOCTL_SUBMIT, &job);
```

`write()` accepts one non-empty, four-byte-aligned RISC-V image of at most
4096 bytes. `SUBMIT` accepts between 1 and 32 words, blocks for at most five
seconds, and returns only after Snitch is back in reset and outputs are safe to
read.

## Driver Responsibilities

[`driver/snitch_job.c`](driver/snitch_job.c) performs the complete lifecycle:

1. Map the HPS lightweight bridge at `0xff200000` inside the kernel.
2. Refuse to load unless block ID, boot window, and data window match H3.
3. Resolve Cyclone V `f2h_irq0` through GIC SPI 40.
4. Expose one exclusive-open `/dev/snitch_job` misc device.
5. Hold Snitch in reset while loading code or changing descriptors.
6. Convert `struct h6_job` into the H4 descriptor in shared M10K.
7. Clear pending state, enable IRQ, and release Snitch.
8. Sleep on a kernel wait queue until the interrupt handler increments the
   event count, or fail on timeout/signal.
9. Capture completion before reset, reassert reset, and wait for
   `result_valid` to clear.
10. Validate `DONE`, status, and completion before returning output words.

The driver mutex and exclusive open prevent a second process or firmware
upload from changing shared state during an active job. Error paths leave the
cluster held in reset.

## Client

[`sw/h6_client_nolibc.c`](sw/h6_client_nolibc.c) is a static ARMv7 executable
using raw Linux syscalls. It opens only these regular/device files:

```text
/tmp/h6_payload.bin    read RISC-V worker
/dev/snitch_job        load worker and submit jobs
```

It submits the same three jobs used by H5, making the H5/H6 comparison about
the Linux boundary rather than changing the accelerator workload.

## Reproduce

Build the RISC-V worker, Linux module, and ARM client:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/h6_linux_job_driver
./scripts/test_build.sh
```

Run the physical test:

```bash
BOARD_SUDO_PASSWORD=temppwd ./scripts/run_board_test.sh
```

The script uses root only to load/unload the kernel module and set the device
policy. The client command itself has no `sudo`; it reports UID 1000. On a
normal distribution, a persistent udev rule should assign a dedicated group
instead of the test script's temporary mode `0666`.

## Physical Result

Verified on the DE1-SoC LXDE Linux image on 2026-07-13:

```text
H6_CLIENT_UID=0x000003e8
H6_PAYLOAD_UPLOADS=0x00000001
H6_JOB0_EVENT=0x00000001
H6_JOB0_LAST_OUTPUT=0x00000011
H6_JOB0_PASS
H6_JOB1_EVENT=0x00000002
H6_JOB1_LAST_OUTPUT=0x0000140b
H6_JOB1_PASS
H6_JOB2_EVENT=0x00000003
H6_JOB2_LAST_OUTPUT=0x00070003
H6_JOB2_PASS
H6_LINUX_JOB_DRIVER_PASS
```

`0x3e8` is decimal UID 1000, the `ubuntu` account. This proves the successful
client process was not root. The driver itself runs in kernel context, as all
Linux hardware drivers do.

## Bring-Up Finding

The first physical client attempt could not open the device even though the
setup command had applied `chmod 666`. The vendor image asynchronously reset
the newly created misc-device node to mode `0600` after module insertion. The
test now waits for `/dev/snitch_job` and a short device-manager settling period
before applying and verifying permissions. The failed attempt stopped at
`open()` and did not release Snitch or submit a job.

## Current Limitations

- The test uses a temporary world-readable/writable device mode rather than a
  persistent group-based udev policy.
- Firmware authenticity is not checked; device access is the trust boundary.
- One process and one in-flight job are allowed.
- Snitch resets and restarts the same worker for each job.
- ARM and Snitch do not access shared RAM simultaneously.
- The H4 transform worker is still an educational fixed operation.

The next logical milestone is H7: add a hardware job doorbell and safe
shared-memory arbitration so a resident Snitch worker can accept another job
without resetting the cluster between submissions.
