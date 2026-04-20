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

It explicitly did not target:

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
```

This is now a real heterogeneous control-path plus data-path proof.
It is stronger than "the simulator builds" but still smaller than a real
HeroSDK runtime/OpenMP proof.

## What Was Added

Repo-side additions on this branch:

- `scripts/bootstrap-local-occamy-minimal.sh`
- `scripts/run-local-occamy-minimal.sh`
- `LOCAL_OCCAMY_MINIMAL.md`
- `LOCAL_OCCAMY_MINIMAL_ARCH.md`
- a branch-specific README note

Matching Occamy fork branch contents:

- `franchecol/occamy` branch `occamy-minimal-bootstrap`
- Verilator compatibility fix in `target/sim/Makefile`
- `target/sim/sw/device/apps/minimal_irq/`
- `target/sim/sw/device/apps/roundtrip/`
- `target/sim/sw/host/apps/roundtrip/`

Runtime/workflow additions made by the bootstrap path:

- clone `platforms/occamy` from `franchecol/occamy` on branch
  `occamy-minimal-bootstrap` if it is missing
- check that an existing `platforms/occamy` checkout already matches that fork
  branch
- verify that the expected Occamy branch contents are present
- create `.venv-occamy`
- install Python generation dependencies
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
- host trace:
  `platforms/occamy/target/sim/trace_hart_00.dasm`
- device trace:
  `platforms/occamy/target/sim/logs/trace_hart_00001.dasm`

What the traces demonstrate:

- the device trace shows the Snitch payload reading `mhartid` and performing
  the interrupt store
- for `roundtrip`, the device trace also shows stores into the shared buffer
  region before the interrupt store
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
- the path is automated enough for reuse
- the branch documents system prerequisites and machine setup
- the scripts are more Linux-portable than the first local version

What is still not true:

- we have not yet proven a real HeroSDK runtime/offload path
- we have not yet validated FPGA bring-up for this reduced path
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

Status: next recommended milestone

Success criteria:

- execute a slightly richer device-side workload than raw handwritten IRQ-only
  assembly
- exercise more of the intended Occamy/HeroSDK software shape
- identify the exact boundary where the full runtime or OpenMP path breaks

Why this matters:

- it tells us whether the next real blocker is in runtime integration,
  compilation, or platform assumptions

### M3: Reduced FPGA Bring-Up

Status: deferred until after more simulation confidence

Success criteria:

- move the reduced path onto FPGA only after M1 or M2 gives higher confidence
- keep the experiment narrow enough that failures can be attributed to board,
  boot, or hardware effects rather than basic host/device contract issues

Why this is not the immediate next step:

- FPGA adds boot images, board-specific flow, bitstream generation, and
  hardware debugging on top of the existing software uncertainty

### M4: Upstream-Oriented Cleanup

Status: optional future milestone

Success criteria:

- reduce the branch-local hacks where possible
- upstream a minimal Verilator compatibility fix or workflow note
- document the reduced flow in a form that could be reviewed outside this fork

## Recommended Next Step

The best next technical step is now M2, not FPGA.

That means:

- stay in simulation
- keep the reduced Occamy single-cluster configuration
- move one step closer to the intended HeroSDK software shape
- keep the workload tiny enough that failures are still attributable

Short version:

```text
Current state:
  control-path and minimal data-path proofs work

Best next state:
  a runtime-shaped simulation proof works

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
