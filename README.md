# hero-tools Occamy Minimal Branch

This fork branch adds a reduced local Occamy flow for staged HeroSDK/Occamy
validation.

Branch identity:

```text
hero-tools fork:  franchecol/hero-tools
hero-tools branch: occamy-minimal-bootstrap
Occamy fork:      franchecol/occamy
Occamy branch:    occamy-minimal-bootstrap
cva6-sdk fork:    franchecol/cva6-sdk
cva6-sdk branch:  occamy-minimal-bootstrap
```

Current branch status:

```text
M0: completed minimal control-path proof in Verilator.
M1: completed shared-memory data-path proof in Verilator.
M2: completed reduced axpy offload proof using the HeroSDK RV32 LLVM path.
M3: frozen HeroSDK/OpenMP simulation proof.
M4: next milestone, reduced FPGA bring-up.
```

The M3 freeze is not a full live qemu-to-Verilator device model.  It proves
that the HeroSDK/OpenMP cva6/occamy stack builds, qemu reaches the Occamy
OpenMP plugin, all 16 captured OpenMP launches can be gated on Verilator replay
success, and the five `map(tofrom)` launches receive replay-derived W32
copybacks without the benchmark printing `Error: map to_from did not work`.

The next intended step is FPGA bring-up with the tiny
`apps/omp/basic/map_tofrom_u32` probe, not further expansion of the
qemu/Verilator replay bridge.

## Start Here

On a stock Arch Linux install:

```bash
sudo pacman -Syu
sudo pacman -S --needed base-devel git python ripgrep bc dtc verilator bender riscv64-elf-gcc qemu-user
```

On Debian/Ubuntu/Mint and similar distributions, install equivalent tools and
use the same repo-side commands.

Fresh checkout:

```bash
git clone https://github.com/franchecol/hero-tools.git
cd hero-tools
git switch occamy-minimal-bootstrap
./scripts/bootstrap-local-occamy-minimal.sh
```

For full M0-through-M3 reproduction, initialize the HeroSDK submodules before
the M2/M3 builds:

```bash
git submodule update --init --recursive cva6-sdk toolchain/llvm-project sw/libhero/vendor/o1heap
```

Current reproducibility scope:

```text
M0/M1: expected to reproduce from this branch, the matching Occamy fork, and
       the listed Linux dependencies.
M2:    expected to reproduce after the LLVM/o1heap submodules are initialized.
M3:    source state is now pinned through the matching cva6-sdk fork branch.
       A clean-machine revalidation is still recommended after checkout.
```

Useful reruns:

```bash
./scripts/run-local-occamy-minimal.sh roundtrip
source scripts/setenv.sh
make hero-tc-llvm-axpy
./scripts/run-local-occamy-minimal.sh axpy
./scripts/run-local-occamy-openmp-replay-bridge.sh --all
```

## Local Docs

The branch-local docs have been consolidated to avoid conflicting runbooks:

```text
LOCAL_OCCAMY.md
  M3 freeze status, local setup, reproduction commands, evidence, caveats,
  and milestone summary.

LOCAL_OCCAMY_FPGA_BRINGUP.md
  M4 handoff: VCU128-oriented FPGA path, first correctness probe,
  milestones, and stop conditions.
```

The older root-level notes `LOCAL_OCCAMY_MINIMAL.md`,
`LOCAL_OCCAMY_MINIMAL_ARCH.md`, and `LOCAL_OCCAMY_MINIMAL_STATUS.md` were merged
into `LOCAL_OCCAMY.md`.

## Upstream HeroSDK

HeroSDK is an open-research software development kit for heterogeneous RISC-V
platforms.  It enables accelerated Linux userspace applications using OpenMP
target for programmable multi-core clusters.  The upstream project currently
targets Carfield and Occamy.

HeroSDK continues the Hero and HeroV2 line, but those projects are not yet
compatible with this repository.  Use the original Hero repository for work
that specifically refers to HeroV2.

HeroSDK is developed as part of the PULP project, a joint effort between ETH
Zurich and the University of Bologna.

## Upstream Repository Layout

```text
apps/
  Example OpenMP applications.

artifacts/
  Automatically managed artifact cache.

cva6-sdk/
  Buildroot-based CVA6 SDK submodule.

docs/
  Documentation sources.

install/
  Generated LLVM, binaries, libraries, and device newlibs.

output/
  Generated intermediate build output.

platforms/
  Hardware platforms cloned on demand.

scripts/
  Helper scripts.

sw/
  Hero runtime library, LLVM libraries, OpenMP target runtime, and drivers.

toolchain/
  LLVM fork containing the Hero OpenMP target runtime implementation.
```

Generated directories such as `install/`, `output/`, and `platforms/` can be
large and are not part of the small source-only view of the branch.

## Upstream Dependencies

HeroSDK uses:

- `cva6-sdk` for Linux images through Buildroot.
- `llvm-project` for the heterogeneous compiler and OpenMP target runtime.
- `o1heap` for device-side dynamic memory allocation.

## License

Unless specified otherwise in individual file headers, software sources in this
repository are licensed under Apache 2.0.
