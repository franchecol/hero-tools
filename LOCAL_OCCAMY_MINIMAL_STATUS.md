# Local Occamy Minimal Status And Milestones

Status: current branch-local status note for `occamy-minimal-bootstrap`.

This document is not a general HeroSDK charter.
It only describes the reduced local Occamy path that was developed and
validated in this fork branch.

## Purpose

The goal of this work was to establish the smallest reproducible heterogeneous
Occamy proof that can run locally without requiring the full documented
HeroSDK FPGA/Linux bring-up flow.

In particular, this effort focused on:

- local RTL simulation
- a reduced single-cluster Occamy configuration
- a CVA6 host binary
- a tiny Snitch-side device payload
- a verified host/device completion path

The original reduced proof explicitly did not target:

- the full HeroSDK LLVM/OpenMP flow
- `make hero-cva6-sdk-all`
- VCU128 FPGA bitstream bring-up
- Linux image generation
- PCIe or HPC-style platforms

## Current Outcome

The reduced path is now validated end to end on this machine.

What was proven:

```text
M0 control path
  CVA6 host ELF
    -> programs Snitch entry point
    -> wakes the cluster
    -> waits for host software interrupt

  Snitch device payload
    -> hart 1 executes
    -> writes CLINT host-MSIP
    -> parks in WFI

  Simulator
    -> host resumes
    -> host reaches _exit
    -> host writes tohost
    -> simulation exits cleanly

M1 data path
  CVA6 host ELF
    -> initializes a 16-word shared buffer
    -> passes the buffer pointer through comm_buffer.usr_data_ptr
    -> wakes the cluster and waits for completion
    -> validates the returned buffer contents

  Snitch device payload
    -> hart 1 reads the shared pointer
    -> increments all 16 words in place
    -> signals host completion through CLINT host-MSIP

  Simulator
    -> device trace shows stores into the shared buffer region
    -> host validates the modified buffer
    -> host writes tohost and exits with code 0

M2 runtime-shaped proof
  CVA6 host offload flow
    -> performs the partial build and emits origin.ld
    -> embeds axpy.bin into offload-axpy.elf
    -> launches the existing verification harness

  Snitch device payload
    -> builds with the HeroSDK RV32 LLVM toolchain and sysroot
    -> links against the required device runtime and math libraries
    -> executes the reduced axpy workload

  Simulator and verifier
    -> run to completion through the upstream verify.py path
    -> report success for the reduced offload proof

M3 HeroSDK-shaped build and runtime smoke proof
  HeroSDK OpenMP application flow
    -> builds the cva6/occamy libhero and libomp runtime stack
    -> builds the Occamy device-side libomptarget_device archive
    -> compiles apps/omp/basic/offload_benchmark with DEVICES=occamy
    -> runs the custom HERCULES LLVM passes
    -> emits a RISC-V Linux host ELF with an embedded RV32 device image

  qemu-riscv64 smoke run
    -> runs the generated RISC-V Linux host ELF against the Buildroot sysroot
    -> provides libhero_occamy.so, libomp.so, and libomptarget.so
    -> loads libomptarget.rtl.herodev_occamy.so
    -> registers the embedded Occamy target image
    -> reaches __tgt_rtl_init_device(1)

  fake-driver smoke run
    -> LD_PRELOADs a RISC-V user-space shim for the Occamy driver ABI
    -> answers the libhero open/ioctl/mmap calls for /dev/occamydev--1
    -> provides fake SOC control, quadrant control, CLINT, L2, L3, and
       Snitch-cluster memory maps
    -> lets the OpenMP RTL initialize device 1
    -> loads the embedded RV32 target image into the fake L3 map
    -> resolves the four OpenMP target entry symbols
    -> reaches the first __tgt_rtl_run_target_region launch

  fake-completion smoke run
    -> extends the same shim by interposing hero_dev_mbox_write/read
    -> recognizes the MBOX_DEVICE_START launch sequence
    -> returns MBOX_DEVICE_DONE and a fake device cycle count
    -> lets the host OpenMP runtime complete its target-launch control path

  real mailbox-runtime smoke run
    -> builds a bare-metal CVA6 host app and RV32 Snitch payload
    -> runs the Snitch-side libomptarget_device mailbox manager in Verilator
    -> sends the same four launch words used by the HeroSDK OpenMP RTL:
       MBOX_DEVICE_START, target entry, argument pointer, and thread count
    -> calls a tiny target function through that manager
    -> writes 0x12345679 into host-visible memory
    -> returns MBOX_DEVICE_DONE, cycles, and dma-wait cycles to the host

  Current caveat
    -> final host link still relies on --noinhibit-exec for an .eh_frame
       relocation diagnostic emitted by GNU ld
    -> the no-shim smoke run stops at device initialization because this
       machine does not expose /dev/occamydev--1
    -> the fake-driver smoke run stops at target launch because no Snitch-side
       runtime is connected to consume the mailbox request and send completion
    -> the fake-completion smoke run intentionally does not execute target code,
       so map(tofrom) correctness is not proven and the benchmark reports
       "Error: map to_from did not work"
    -> the real mailbox-runtime smoke is not yet wired to the Linux/qemu
       HeroSDK OpenMP host process; it proves the device-side protocol in
       Verilator, not the full user-facing OpenMP map/tofrom flow
```

This is now a real heterogeneous control-path plus data-path proof.
It is stronger than "the simulator builds" and stronger than the branch-local
roundtrip, but it is still smaller than a real user-facing HeroSDK OpenMP
target proof that has executed its target regions end to end.

## What Was Added

Repo-side additions on this branch:

- `scripts/bootstrap-local-occamy-minimal.sh`
- `scripts/run-local-occamy-minimal.sh`
- `scripts/run-local-occamy-openmp-smoke.sh`
- `sw/libhero/sim/occamy_fake_driver.c`
- `scripts/run-local-occamy-minimal.sh omp_mailbox` mode for a real
  Snitch-side mailbox-runtime smoke
- `LOCAL_OCCAMY_MINIMAL.md`
- `LOCAL_OCCAMY_MINIMAL_ARCH.md`
- a branch-specific README note
- `hero.mk` target `hero-tc-llvm-axpy`
- `toolchain/setup-llvm-device.sh` fixes for the reduced RV32 LLVM path
- `toolchain/llvm-support/CMakeLists.txt` fix for modern CMake/GCC behavior
- `apps/omp/common/default.mk` fixes for the Occamy OpenMP build path:
  libomp headers, no-relax host compilation, and a temporary GNU ld
  `--noinhibit-exec` workaround
- `sw/libhero` type/API cleanup needed to build `libhero_occamy.so` against
  the current headers and toolchain

Matching Occamy fork branch contents:

- `franchecol/occamy` branch `occamy-minimal-bootstrap`
- Verilator compatibility fix in `target/sim/Makefile`
- `target/sim/sw/device/apps/minimal_irq/`
- `target/sim/sw/device/apps/roundtrip/`
- `target/sim/sw/host/apps/roundtrip/`
- `target/sim/sw/device/toolchain.mk` fix for the reduced `axpy` builtins path
- `target/sim/sw/device/apps/libomptarget_device/Makefile` default-goal fix so
  plain `make` builds the device-side archive instead of selecting `clean`
- `target/sim/sw/device/apps/omp_mailbox/`
- `target/sim/sw/host/apps/omp_mailbox/`

Runtime/workflow additions made by the bootstrap path:

- clone `platforms/occamy` from `franchecol/occamy` on branch
  `occamy-minimal-bootstrap` if it is missing
- check that an existing `platforms/occamy` checkout already matches that fork
  branch
- verify that the expected Occamy branch contents are present
- create `.venv-occamy`
- install Python generation dependencies
- install `numpy` and `pyelftools` when the `axpy` verifier needs them
- build the reduced simulator
- build host/device binaries
- run the simulation
- verify traces

## Evidence

Known-good output artifacts:

- host ELF:
  `platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf`
- device binary:
  `platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin`
- roundtrip host ELF:
  `platforms/occamy/target/sim/sw/host/apps/roundtrip/build/roundtrip.elf`
- roundtrip device binary:
  `platforms/occamy/target/sim/sw/device/apps/roundtrip/build/roundtrip.bin`
- `axpy` host ELF:
  `platforms/occamy/target/sim/sw/host/apps/offload/build/offload-axpy.elf`
- `axpy` device binary:
  `platforms/occamy/target/sim/sw/device/apps/blas/axpy/build/axpy.bin`
- HeroSDK/OpenMP host ELF:
  `apps/omp/basic/offload_benchmark/offload_benchmark_occamy.elf`
- HeroSDK/OpenMP device runtime archive:
  `platforms/occamy/target/sim/sw/device/apps/libomptarget_device/build/libomptarget_device.a`
- HeroSDK/OpenMP runtime smoke log:
  `output/occamy-openmp-smoke.log`
- RISC-V fake Occamy driver shim:
  `output/occamy-openmp-smoke/liboccamy_fake_driver.so`
- M3 mailbox-runtime host ELF:
  `platforms/occamy/target/sim/sw/host/apps/omp_mailbox/build/omp_mailbox.elf`
- M3 mailbox-runtime device binary:
  `platforms/occamy/target/sim/sw/device/apps/omp_mailbox/build/omp_mailbox.bin`
- host trace:
  `platforms/occamy/target/sim/trace_hart_00.dasm`
- device trace:
  `platforms/occamy/target/sim/logs/trace_hart_00001.dasm`
- `axpy` verifier outcome:
  `[occamy-minimal] success` and `[occamy-minimal] mode: axpy`
- M3 mailbox-runtime verifier outcome:
  `[occamy-minimal] success` and `[occamy-minimal] mode: omp_mailbox`

What the traces demonstrate:

- the device trace shows the Snitch payload reading `mhartid` and performing
  the interrupt store
- for `roundtrip`, the device trace also shows stores into the shared buffer
  region before the interrupt store
- for `axpy`, the reduced offload flow produces both `offload-axpy.elf` and
  `axpy.bin`, then completes through the upstream verification harness
- for the M3 build proof, `offload_benchmark_occamy.elf` proves that the
  HeroSDK OpenMP compiler flow can compile, unbundle, transform, rebundle, link
  a device image, wrap that image, and emit a Linux host executable for Occamy
- for the M3 runtime smoke, `output/occamy-openmp-smoke.log` proves that the
  host ELF starts under `qemu-riscv64`, loads the Occamy OpenMP RTL plugin,
  registers the embedded device image, and reaches device initialization
- for the M3 fake-driver smoke, the same log proves that the OpenMP RTL gets
  past device initialization, writes the embedded RV32 image into a fake L3
  memory map, resolves the four target-region symbols, and reaches the first
  OpenMP target launch
- for the M3 fake-completion smoke, the same log proves that a fake mailbox
  responder can let the host OpenMP runtime complete its target-launch control
  path, while also showing that target execution and map(tofrom) correctness
  are still missing
- for the M3 mailbox-runtime smoke, the device trace proves that the real
  Snitch-side `libomptarget_device` manager reads the launch sequence, jumps to
  `omp_mailbox_target`, reads `0x12345678` from host-visible memory, stores
  `0x12345679` back, and returns `MBOX_DEVICE_DONE` through the mailbox
- the host trace shows the host clearing the software interrupt, validating the
  returned buffer, and reaching the final `tohost` exit write

## What Made This Hard

The main difficulty was not that Occamy can only work on FPGA.
The main difficulty was that the documented and better-integrated paths in the
repo are larger and different from the reduced proof we wanted.

Three concrete gaps mattered:

1. The official Occamy docs are biased toward the broader FPGA/CVA6-SDK/U-Boot
   bring-up flow.

2. The simulation tree contains Verilator support, but some automation still
   treats Questasim as the primary simulator path.

3. Current local Verilator builds needed compatibility fixes that were not
   already packaged into a simple first-class workflow.

So the work here was partly technical and partly integrative:

- isolate the smallest target worth proving
- patch current Verilator compatibility
- bypass the Questasim-oriented path where necessary
- turn the result into a reproducible branch workflow

## Current Boundaries

What is true now:

- the minimal heterogeneous simulation path works
- the branch now contains both a control-path proof and a minimal data-path
  proof
- the branch now also contains a reduced runtime-shaped `axpy` offload proof
- the branch can now build a user-facing HeroSDK OpenMP target application for
  `DEVICES=occamy`
- the generated HeroSDK/OpenMP host ELF now runs far enough under `qemu-riscv64`
  to enter the Occamy OpenMP target plugin and attempt device initialization
- the fake-driver smoke now moves the boundary past the Linux driver ABI and
  reaches OpenMP target launch
- the fake-completion smoke now moves the host-side boundary through OpenMP
  target-launch completion by faking mailbox responses
- the real mailbox-runtime smoke now proves that the Snitch-side
  `libomptarget_device` manager can consume the HeroSDK launch protocol and
  execute a target-function pointer in Verilator
- the path is automated enough for reuse
- the branch documents system prerequisites and machine setup
- the scripts are more Linux-portable than the first local version
- the reduced RV32 LLVM device toolchain path now works for `rv32imafd-ilp32d`
- the M3 OpenMP build currently emits an ELF only with the GNU ld
  `--noinhibit-exec` workaround

What is still not true:

- we have not yet executed the user-facing HeroSDK OpenMP target regions on the
  Snitch-side device runtime
- we do not yet have a real `/dev/occamydev--1` endpoint, only a local
  user-space ABI shim for smoke testing
- we do not yet have the Linux/qemu HeroSDK OpenMP host process connected to the
  real Verilator Snitch-side runtime
- we have not yet validated OpenMP `map(to)` / `map(tofrom)` correctness
  through actual Snitch-side target execution
- we have not yet validated FPGA bring-up for this reduced path
- we do not yet have an upstream-clean linker solution for the `.eh_frame`
  relocation diagnostic in the generated offload wrapper object
- this work is not upstreamed into `pulp-platform/hero-tools` or
  `pulp-platform/occamy`

## Milestones

The most useful way to view the work now is as staged milestones.

### M0: Reproducible Heterogeneous Control-Path Proof

Status: completed

Success criteria:

- reduced Occamy configuration builds locally
- Verilator simulator builds locally
- CVA6 host starts a Snitch payload
- Snitch payload signals host completion
- traces prove both host and device executed the expected path
- flow is packaged into a reusable bootstrap/run workflow

Delivered:

- completed

### M1: Minimal Heterogeneous Data-Path Proof

Status: completed

Success criteria:

- host provides a small input buffer
- Snitch reads the input data
- Snitch writes back a deterministic result
- host verifies the returned data in simulation

Why this matters:

- it moves the proof from "interrupt handshake works" to "host/device state
  exchange works"
- it is still much cheaper than FPGA bring-up
- it reduces the risk that later FPGA failures are really software-contract
  failures

Suggested scope:

- one tiny buffer
- one simple transform such as increment, scale, xor, or reduction
- keep the reduced single-cluster configuration

Delivered:

- completed with a 16-word in-place increment roundtrip
- validated in simulation with host return code `0`
- trace-backed proof that the device touched shared data, not only the IRQ path

### M2: Runtime-Shaped Simulation Proof

Status: completed

Success criteria:

- execute a slightly richer device-side workload than raw handwritten IRQ-only
  assembly
- exercise more of the intended Occamy/HeroSDK software shape
- identify the exact boundary where the full runtime or OpenMP path breaks

Why this matters:

- it tells us whether the next real blocker is in runtime integration,
  compilation, or platform assumptions

Validated candidate:

- use the existing Occamy `offload` host path with `device/apps/blas/axpy`
- this is stronger than the branch-local `roundtrip` proof because it uses the
  existing BLAS device workload, `snrt`, DMA movement, and the offload
  packaging flow

Delivered:

- completed with the existing Occamy `offload` host path and
  `device/apps/blas/axpy`
- validated after building `make hero-tc-llvm-axpy`
- reduced local flow now builds the device runtime and math libraries before
  finalizing the host ELF
- the verifier completes successfully and reports the reduced `axpy` proof as a
  success

### M3: HeroSDK-Shaped Software Proof

Status: real mailbox-runtime smoke completed; full user-facing OpenMP
map/tofrom execution still pending

Success criteria:

- execute one small user-facing software case that is closer to the intended
  HeroSDK value than the current Occamy-specific harnesses
- exercise more of the heterogeneous compiler/runtime path than the current
  handwritten `minimal_irq` / `roundtrip` pair
- identify whether the next blocker is in OpenMP/plugin/runtime integration or
  in platform assumptions

Completed build-level subset:

- `make HERO_HOST=cva6 HERO_DEVICE=occamy hero-sw-all` builds
  `libhero_occamy.so`, `libomptarget.rtl.herodev_occamy.so`, and `omp.h`
- the custom HERCULES LLVM pass wrapper and pass libraries are installed:
  `hc-omp-pass`, `libOmpKernelWrapper.so`, and
  `libOmpHostPointerLegalizer.so`
- the Occamy device runtime archive builds:
  `libomptarget_device.a`
- `apps/omp/basic/offload_benchmark` builds with `DEVICES=occamy`
- the build emits:
  `apps/omp/basic/offload_benchmark/offload_benchmark_occamy.elf`

Completed runtime-smoke subset:

- `scripts/run-local-occamy-openmp-smoke.sh` runs the host ELF under
  `qemu-riscv64`
- the smoke run uses the Buildroot RISC-V Linux sysroot and the locally built
  HeroSDK shared libraries
- `libomptarget` loads `libomptarget.rtl.herodev_occamy.so`
- the embedded Occamy device image is accepted as compatible by the HERO RTL
- execution reaches `Target HERO RTL --> __tgt_rtl_init_device(1)`
- the current run stops at `Failed to init device 1`, which is expected on this
  machine because there is no `/dev/occamydev--1` device interface

Completed fake-driver subset:

- `scripts/run-local-occamy-openmp-smoke.sh --fake-driver` builds and uses a
  RISC-V `LD_PRELOAD` shim from `sw/libhero/sim/occamy_fake_driver.c`
- the shim implements the driver ABI subset used by libhero:
  `open`, `ioctl`, `mmap`, `munmap`, and `close`
- the OpenMP RTL gets past `__tgt_rtl_init_device(1)`
- the embedded RV32 image is loaded into the fake L3 memory map
- the four target entry symbols from `offload_benchmark/main.c` are resolved
- execution reaches `Target HERO RTL --> __tgt_rtl_run_target_region(..)`
- the current run times out there, which is expected because no Snitch-side
  runtime is consuming the mailbox request

Completed fake-completion subset:

- `scripts/run-local-occamy-openmp-smoke.sh --fake-complete` enables the same
  fake driver plus `OCCAMY_FAKE_DEVICE_COMPLETE=1`
- the shim interposes `hero_dev_mbox_write` and `hero_dev_mbox_read`
- the shim observes the target-launch mailbox sequence and returns
  `MBOX_DEVICE_DONE` plus a fake device cycle count
- the host OpenMP runtime completes all target-region control-flow steps and
  deinitializes cleanly
- the run still reports `Error: map to_from did not work`, which is expected
  because the fake responder does not execute any Snitch-side target function

Completed real mailbox-runtime subset:

- `scripts/run-local-occamy-minimal.sh omp_mailbox` builds a bare-metal host
  app plus an RV32 Snitch payload that links the real `libomptarget_device`
  mailbox manager
- the host app sends `MBOX_DEVICE_START`, target function address, argument
  pointer, and thread count through the same software mailbox protocol used by
  the HeroSDK OpenMP RTL
- the Snitch-side manager calls `omp_mailbox_target`
- `omp_mailbox_target` reads `0x12345678` from host-visible memory and writes
  `0x12345679` back
- the Snitch-side manager returns `MBOX_DEVICE_DONE` plus cycle counters
- the host validates the returned word and exits with code `0`

Known build caveat:

- the final host link uses GNU ld with `--noinhibit-exec`
- GNU ld still reports a dangerous `.eh_frame` relocation in the generated
  offload wrapper object
- this is acceptable for the current local build proof, but it is not an
  upstream-quality toolchain fix

Still missing for full M3:

- replace the fake user-space driver shim with either the real Occamy Linux
  driver or a simulator bridge that talks to Verilator
- connect the Linux/qemu HeroSDK OpenMP host process to the running Verilator
  Snitch-side runtime
- prove that the generated `offload_benchmark` target regions reach the
  Snitch-side runtime through that connected endpoint
- verify the `map(to)` and `map(tofrom)` behavior from
  `offload_benchmark/main.c`

Why this is the immediate next step:

- it answers the actual "why HeroSDK instead of pure Occamy?" question more
  directly
- it keeps debugging in simulation, where failures are still attributable and
  cheap to reproduce

### M4: Reduced FPGA Bring-Up

Status: deferred until after M3

Success criteria:

- move the reduced path onto FPGA only after the simulation-side software proof
  is stronger
- keep the experiment narrow enough that failures can be attributed to board,
  boot, or hardware effects rather than basic host/device contract issues

Why this is not the immediate next step:

- FPGA adds boot images, board-specific flow, bitstream generation, and
  hardware debugging on top of the existing software uncertainty

### M5: Upstream-Oriented Cleanup

Status: optional future milestone

Success criteria:

- reduce the branch-local hacks where possible
- upstream a minimal Verilator compatibility fix or workflow note
- document the reduced flow in a form that could be reviewed outside this fork

## Recommended Next Step

The best next technical step is now M3 target-region execution, not FPGA.

That means:

- stay in simulation
- keep the reduced Occamy single-cluster configuration
- keep the M3 build and runtime-smoke proofs frozen as the baseline
- move from "the host and device halves are proven separately" to "the
  generated OpenMP host ELF drives the real Verilator Snitch-side runtime"
- keep the workload tiny enough that failures are still attributable

Short version:

```text
Current state:
  M0, M1, and M2 work in simulation
  M3 builds a HeroSDK/OpenMP offload ELF for Occamy
  M3 smoke-runs that ELF far enough to load the Occamy OpenMP target plugin
  M3 fake-driver smoke reaches target launch
  M3 fake-completion smoke completes the host OpenMP control path
  M3 omp_mailbox runs the real Snitch-side mailbox manager and target function

Best next state:
  the generated OpenMP ELF executes a target region through a real
  Verilator-connected or kernel-driver-connected Occamy endpoint

Then:
  consider reduced FPGA bring-up
```

## Branch Context

This work currently lives in:

- fork: `franchecol/hero-tools`
- branch: `occamy-minimal-bootstrap`
- matching Occamy fork: `franchecol/occamy`
- matching Occamy branch: `occamy-minimal-bootstrap`

The fork default branch may remain close to upstream.
The reduced path lives on the dedicated branch above.

## Related Notes

- `LOCAL_OCCAMY_MINIMAL.md`
- `LOCAL_OCCAMY_MINIMAL_ARCH.md`
