# Local Occamy M3b OpenMP Replay Freeze

This document is the detailed evidence and reproduction runbook for M3b on
`occamy-minimal-bootstrap`.

For the authoritative M0-through-M4 progression and document index, start with
the [Local Occamy Milestone Roadmap](local-occamy-roadmap.md).

It merges the former root notes:

```text
LOCAL_OCCAMY_MINIMAL.md
LOCAL_OCCAMY_MINIMAL_ARCH.md
LOCAL_OCCAMY_MINIMAL_STATUS.md
```

## What This Branch Is

The goal is to keep a smallest-useful HeroSDK/Occamy proof that can run locally
before moving to FPGA bring-up.

This branch focuses on:

- reduced single-cluster Occamy simulation
- open-source Verilator execution
- CVA6 host binaries
- Snitch-side device payloads
- HeroSDK/OpenMP cva6/occamy build and runtime smoke coverage
- trace-backed evidence for the current M3b freeze

It does not attempt to be a general HeroSDK replacement, a full Occamy
simulator product, or a complete FPGA runbook.

For a detailed first-principles explanation of the M0 proof, including source
files, registers, trace markers, waveform signals, debugging history, and
branch commits, read the
[M0 Deep Dive](local-occamy-m0-deep-dive.md).

For a device-side comparison between the official standalone Snitch tutorial
flow and this branch's Occamy-wrapped Snitch payload flow, read the
[Device-Side Snitch Comparison](local-occamy-device-side-snitch-comparison.md).

## Current Status

```text
M0: completed
  Minimal heterogeneous control-path proof.
  CVA6 starts a Snitch payload, Snitch signals host completion, simulation exits.

M1: completed
  Minimal shared-memory data-path proof.
  Snitch increments a 16-word host-provided buffer and host verifies it.

M2: completed
  Reduced runtime-shaped axpy proof.
  Existing Occamy offload host path packages and verifies a reduced axpy run.

M3a: completed
  Deterministic live mailbox-runtime proof in Verilator.
  The real Snitch mailbox manager calls a target and returns its result.

M3b: frozen
  HeroSDK/OpenMP cva6/occamy software proof.
  qemu host reaches the Occamy OpenMP plugin.
  all 16 captured OpenMP launches replay through the real Snitch mailbox manager.
  the replay bridge gates qemu progress on Verilator success for all 16 launches.
  five map(tofrom) launches receive W32 copybacks.

M4: next
  Reduced FPGA bring-up with apps/omp/basic/map_tofrom_u32.
```

The current M3b freeze command is:

```bash
./scripts/run-local-occamy-openmp-replay-bridge.sh --all
```

Expected M3b evidence:

```text
16 response files under output/occamy-openmp-bridge/responses/
5 W32 copybacks in responses 4, 7, 10, 13, and 16
no "Error: map to_from did not work" in output/occamy-openmp-smoke.log
```

The W32 copyback line is:

```text
W32 0xc08003a0 0x0000000a
```

## Boundaries

What is true:

- The reduced local Verilator path works.
- The HeroSDK/OpenMP cva6/occamy build path works locally.
- The qemu host can reach the Occamy OpenMP target plugin.
- The fake driver can model the subset of `/dev/occamydev--1` needed for M3b
  smoke testing.
- Captured OpenMP launches can be replayed through the real Snitch-side
  `libomptarget_device` mailbox manager.
- The replay bridge can block qemu host progress until Verilator replay
  succeeds.
- For this benchmark, trace-derived W32 copyback fixes the observed
  `map(tofrom)` checks.

What is not true:

- There is no real `/dev/occamydev--1` endpoint on this local machine.
- The qemu host is not connected to one continuously running Verilator device.
- The W32 copyback bridge is not a general coherent qemu/Verilator memory
  system.
- The reduced path has not yet been validated on FPGA.
- The OpenMP host link still relies on the local GNU ld `--noinhibit-exec`
  workaround for the known `.eh_frame` relocation diagnostic.

## Fresh Machine Setup

Arch packages:

```bash
sudo pacman -Syu
sudo pacman -S --needed base-devel git python ripgrep bc dtc verilator bender riscv64-elf-gcc qemu-user
```

Package purpose:

```text
base-devel      host build tools for Verilator C++ output
git             source checkout and platform clone
python          venv and Python generation tools
ripgrep         rg, used by scripts and checks
bc              simulator build helper
dtc             device tree compiler
verilator       RTL simulator frontend
bender          Occamy hardware dependency manager
riscv64-elf-gcc bare-metal RISC-V toolchain on Arch
qemu-user       qemu-riscv64 for M3b OpenMP smoke tests
```

Cross-distro notes:

- The scripts are not Arch-specific.
- On Debian/Ubuntu/Mint, install equivalent packages.
- If your bare-metal toolchain prefix is different, use
  `RISCV_TOOL_PREFIX=<prefix>`.
- If Verilator is installed in a non-standard location, use
  `VERILATOR_ROOT=/path/to/share/verilator`.

Disk budget observed on this machine:

```text
.venv-occamy       about 101M
install            about 319M
output             about 1.1G
platforms/occamy   about 2.2G
```

Keep at least 4 GiB free for baseline work.  Keep closer to 8 GiB free if you
also rebuild the reduced LLVM/device-toolchain pieces.

## Fresh Checkout

```bash
git clone https://github.com/franchecol/hero-tools.git
cd hero-tools
git switch occamy-minimal-bootstrap
./scripts/bootstrap-local-occamy-minimal.sh
```

The bootstrap path is enough for the M0 baseline and prepares the matching
Occamy fork checkout. For M2, M3a, and M3b, initialize the relevant HeroSDK
submodules too:

```bash
git submodule update --init --recursive cva6-sdk toolchain/llvm-project sw/libhero/vendor/o1heap
```

The bootstrap script:

- clones `platforms/occamy` from `franchecol/occamy` if missing
- verifies the matching Occamy branch
- creates `.venv-occamy`
- installs Python generation dependencies
- creates RISC-V tool prefix compatibility symlinks when needed
- builds the reduced single-cluster simulator
- builds the M0 host/device binaries
- runs the M0 simulation
- verifies the expected traces

Expected M0 success:

```text
[occamy-minimal] success
[occamy-minimal] host ELF: .../offload-minimal_irq.elf
[occamy-minimal] device binary: .../minimal_irq.bin
```

## Clean-Machine Reproducibility

Current source-only status:

```text
M0: expected to reproduce from a fresh Linux checkout with the listed packages.
M1: expected to reproduce after M0 bootstrap.
M2: expected to reproduce after initializing toolchain/llvm-project and o1heap.
M3a: deterministic wrapper, source trees, compiler, artifacts, and trace
     behavior are pinned.
M3b: source state is pinned through franchecol/cva6-sdk, branch
     occamy-minimal-bootstrap. A clean-machine revalidation is still
     recommended before calling the full replay path externally proven.
```

The `cva6-sdk` submodule pointer is intentionally pinned to the matching fork
branch because the M3b build needs Buildroot configuration and nested submodule
updates that were not present at the previous upstream submodule pointer.

The top-level submodule entry is:

```text
url    = https://github.com/franchecol/cva6-sdk.git
branch = occamy-minimal-bootstrap
```

This removes the previous hidden local `cva6-sdk` dependency.  It does not
replace an actual fresh-clone revalidation run; it only makes the source state
explicit and fetchable.

## Common Reruns

M1 roundtrip:

```bash
./scripts/bootstrap-local-occamy-m1.sh
```

M2 axpy:

```bash
./scripts/bootstrap-local-occamy-m2.sh
```

M3a deterministic mailbox-runtime proof:

```bash
./scripts/bootstrap-local-occamy-m3.sh
```

M3b OpenMP build:

```bash
source scripts/setenv.sh
make hero-tc-gcc
make HERO_HOST=cva6 HERO_DEVICE=occamy hero-sw-all
make -C platforms/occamy/target/sim/sw/device/apps/libomptarget_device all
make -C apps/omp/basic/offload_benchmark clean
make -C apps/omp/basic/offload_benchmark DEVICES=occamy
```

M3b frozen bridge run:

```bash
./scripts/run-local-occamy-openmp-replay-bridge.sh --all
```

M4 first software probe build:

```bash
source scripts/setenv.sh
make -C apps/omp/basic/map_tofrom_u32 DEVICES=occamy
```

Expected M4 probe artifact:

```text
apps/omp/basic/map_tofrom_u32/map_tofrom_u32_occamy.elf
```

## Useful Debug Commands

Plain M3b runtime smoke, expected to stop at missing real device endpoint:

```bash
./scripts/run-local-occamy-openmp-smoke.sh
```

Fake-driver smoke, expected to reach first OpenMP target launch:

```bash
./scripts/run-local-occamy-openmp-smoke.sh --fake-driver
```

Fake-completion smoke, expected to complete host control flow without real
target execution:

```bash
./scripts/run-local-occamy-openmp-smoke.sh --fake-complete
```

Capture qemu-side launch descriptors and fake memory snapshots:

```bash
./scripts/run-local-occamy-openmp-smoke.sh --capture-snapshot
```

Replay one captured launch through Verilator:

```bash
./scripts/run-local-occamy-openmp-replay.sh --sequence 4
```

Replay all captured launches offline:

```bash
./scripts/run-local-occamy-openmp-replay.sh --all
```

Run the deterministic M3a Snitch-side mailbox-runtime proof in Verilator:

```bash
./scripts/bootstrap-local-occamy-m3.sh
```

## Important Artifacts

M0 host/device:

```text
platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf
platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin
```

M1 host/device:

```text
platforms/occamy/target/sim/sw/host/apps/roundtrip/build/roundtrip.elf
platforms/occamy/target/sim/sw/device/apps/roundtrip/build/roundtrip.bin
```

M2 host/device:

```text
platforms/occamy/target/sim/sw/host/apps/offload/build/offload-axpy.elf
platforms/occamy/target/sim/sw/device/apps/blas/axpy/build/axpy.bin
```

M3a mailbox runtime:

```text
platforms/occamy/target/sim/sw/host/apps/omp_mailbox/build/omp_mailbox.elf
platforms/occamy/target/sim/sw/device/apps/omp_mailbox/build/omp_mailbox.bin
```

M3b OpenMP:

```text
apps/omp/basic/offload_benchmark/offload_benchmark_occamy.elf
platforms/occamy/target/sim/sw/device/apps/libomptarget_device/build/libomptarget_device.a
output/occamy-openmp-smoke.log
output/occamy-openmp-smoke/launches.jsonl
output/occamy-openmp-smoke/snapshots/snapshots.jsonl
output/occamy-openmp-replay/sequence-XXXX/
output/occamy-openmp-bridge/responses/
```

M4 first probe:

```text
apps/omp/basic/map_tofrom_u32/map_tofrom_u32_occamy.elf
```

## Branch Additions

This branch adds or changes:

- `scripts/bootstrap-local-occamy-minimal.sh`
- `scripts/run-local-occamy-minimal.sh`
- `scripts/run-local-occamy-openmp-smoke.sh`
- `scripts/run-local-occamy-openmp-replay.sh`
- `scripts/run-local-occamy-openmp-replay-bridge.sh`
- `sw/libhero/sim/occamy_fake_driver.c`
- `apps/omp/basic/map_tofrom_u32/`
- `docs/local-occamy-roadmap.md`
- `docs/local-occamy-m3b-openmp-freeze.md`
- `docs/local-occamy-m4-fpga-bringup.md`
- M3b build fixes in the OpenMP/common, libhero, and LLVM support paths
- the `hero-tc-llvm-axpy` reduced device-toolchain target

The matching Occamy fork branch adds the reduced simulator payloads and
compatibility fixes:

```text
franchecol/occamy branch occamy-minimal-bootstrap
```

Key matching Occamy-side additions include:

- `target/sim/sw/device/apps/minimal_irq/`
- `target/sim/sw/device/apps/roundtrip/`
- `target/sim/sw/host/apps/roundtrip/`
- `target/sim/sw/device/apps/omp_mailbox/`
- `target/sim/sw/host/apps/omp_mailbox/`
- Verilator link compatibility updates
- reduced `axpy` builtins path update
- `libomptarget_device` default-goal fix

## Known Caveats

Known OpenMP link diagnostic:

```text
dangerous relocation: Mismatched R_RISCV_SUB_ULEB128 ...
```

The current branch uses GNU ld with `--noinhibit-exec` so the local proof still
emits an ELF.  This is acceptable for the current fork-local proof, but it is
not an upstream-quality toolchain fix.

Expected behavior on a machine without Occamy hardware:

```text
./scripts/run-local-occamy-openmp-smoke.sh
```

This reaches the HeroSDK/OpenMP runtime path and then stops because
`/dev/occamydev--1` is missing.

Expected behavior with fake completion only:

```text
Error: map to_from did not work
```

That is expected because fake completion does not execute target code. The M3b
freeze uses the replay bridge, not plain fake completion, for the stronger
current result.

## Next Step

The next milestone is M4 reduced FPGA bring-up.

Continue with the [M4 FPGA Bring-Up Plan](local-occamy-m4-fpga-bringup.md).

First real-platform success criterion:

```text
map_tofrom_u32_occamy.elf prints:
  PASS map_tofrom_u32: tmp_1=10 tmp_2=10
```

Do not start FPGA validation with AXPY or matrix-vector.  Prove the basic
OpenMP `map(tofrom)` contract first.
