# H4: Linux Job Runtime and Descriptor ABI

H4 turns the H3 debug sequence into one Linux-hosted job submission. One ARM
executable uploads the RISC-V worker, describes a variable-size job in shared
RAM, starts Snitch, blocks on the FPGA interrupt, and validates the returned
descriptor and output array.

H4 is a software-only milestone over the unchanged H3 FPGA image. It does not
add a scheduler, coherent memory, DMA, or new RTL.

```text
ARM Linux host             Shared FPGA memory                 Snitch worker
      │                            │                                │
      ├─ upload RV32 program ─────►│ boot RAM, host 0xff201000      │
      ├─ write descriptor ────────►│ shared RAM +0x000              │
      ├─ write input array ───────►│ shared RAM +0x100              │
      ├─ release reset             │                                │
      │                            │◄── validate descriptor ─────────┤
      │                            │◄── state = RUNNING ─────────────┤
      │                            │◄── write output array ──────────┤
      │                            │◄── state = DONE ────────────────┤
      │◄──── blocking IRQ ─────────│◄── completion 0x4834 ──────────┤
      ├─ assert reset              │                                │
      └─ validate status/output ◄──│ shared RAM +0x200              │
```

## What Changed From H3

```text
H3                              H4
──────────────────────────────────────────────────────────────────────
Shell/devmem2 orchestration     One standalone ARM Linux executable
Fixed four-word worker          Descriptor-selected word count
Implicit input/output layout    Versioned offsets in a shared ABI
One completion signature        READY/RUNNING/DONE/ERROR plus status
Manual expected-value checks    Host validates every returned word
```

The H3 hardware remains useful as the transport. H4 defines how software on
the two processors uses that transport as a job interface.

## Shared ABI

[`include/h4_job_abi.h`](include/h4_job_abi.h) is included by both the ARM C
host and the RISC-V assembly worker. This prevents the two programs from
independently defining descriptor offsets.

The 64-byte descriptor starts at Snitch address `0x4000`, which Linux reaches
at physical address `0xff202000`:

```text
Offset  Field          Owner before start     Owner while/after running
0x00    magic          ARM writes             Snitch validates
0x04    version        ARM writes             Snitch validates
0x08    state          ARM writes READY       Snitch writes RUNNING/DONE/ERROR
0x0c    status         ARM initializes        Snitch writes result status
0x10    count          ARM writes             Snitch validates and consumes
0x14    input_offset   ARM writes             Snitch reads
0x18    output_offset  ARM writes             Snitch reads
0x1c    multiplier     ARM writes             Snitch reads
0x20    bias           ARM writes             Snitch reads
0x24    reserved[7]    ARM clears             Reserved for later ABI versions
```

Input words begin at descriptor offset `0x100`; output words begin at `0x200`.
H4 accepts `1` through `32` words. The worker computes:

```text
output[i] = input[i] * multiplier + bias
```

The state transition is:

```text
ARM: READY ──► Snitch: RUNNING ──► Snitch: DONE
                       │
                       └──────────► Snitch: ERROR + status code
```

Reset remains the memory-ownership boundary inherited from H3. ARM accesses
shared RAM only while Snitch is held in reset. This is not cache coherence or
simultaneous dual-master arbitration.

## Implementation

[`sw/h4_host_nolibc.c`](sw/h4_host_nolibc.c) is a static ARMv7 program using
raw Linux syscalls. It deliberately has no dependency on the old vendor
image's C library. It performs these checks and operations:

1. Read `/tmp/h4_payload.bin` and reject empty, unaligned, or oversized code.
2. Open `/dev/snitch_lite_irq` and map `0xff200000` through `/dev/mem`.
3. Validate the H3 block ID and advertised boot/data RAM windows.
4. Hold Snitch in reset, upload code, and initialize the descriptor and data.
5. Clear and enable the interrupt, release reset, and poll with a 5 s timeout.
6. Check completion `0x4834`, reassert reset, and validate state and outputs.

[`firmware/h4_job.S`](firmware/h4_job.S) is the descriptor-aware RV32IMA
worker. It checks magic, ABI version, count, and both array offsets before
touching the arrays. On success it produces every output, writes `DONE`, and
emits the completion store. Invalid descriptors produce `ERROR` with an
explicit status code and still interrupt the host.

## Reproduce

Build and inspect both processor binaries without the board:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/h4_linux_job_runtime
./scripts/test_abi.sh
```

Run the complete physical test with Linux booted and both USB cables attached:

```bash
BOARD_SUDO_PASSWORD=temppwd ./scripts/run_board_test.sh
```

The board script builds the ARM and RISC-V programs, builds the existing H1
IRQ module for the LXDE kernel, programs the proven H3 SOF, transfers all three
files over UART, loads the driver, and requires `H4_JOB_RUNTIME_PASS`.

## Physical Result

Verified on the DE1-SoC LXDE Linux image on 2026-07-13:

```text
Descriptor count:       6
Multiplier / bias:      5 / 11
Input words:            1, 3, 7, 16, 256, 1024
Completion signature:   0x00004834
Job state / status:     DONE / OK
Output words:           16, 26, 46, 91, 1291, 5131
Result:                 H4_JOB_RUNTIME_PASS
```

The result proves a single ARM application can manage the complete software
job lifecycle across the lightweight bridge, shared M10K, original upstream
Snitch cluster, and FPGA-to-HPS interrupt path.

## Current Limitations

- The host executable contains one fixed demonstration job rather than a
  command-line or library API.
- One job runs at a time; there is no queue or concurrent access.
- The RISC-V program is uploaded for every invocation.
- Shared RAM ownership is enforced by reset, not arbitration or coherence.
- The IRQ kernel module is still installed separately by the test script.

The next logical milestone is H5: make the job interface reusable for multiple
submissions without reloading the kernel module or reprogramming the FPGA.
