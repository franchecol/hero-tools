# hero-tools Occamy Minimal Branch

This fork branch adds a reduced local Occamy flow for staged HeroSDK/Occamy
validation.

Branch identity:

```text
hero-tools fork:   franchecol/hero-tools
hero-tools branch: occamy-minimal-bootstrap
Occamy fork:       franchecol/occamy
Occamy branch:     occamy-minimal-bootstrap
cva6-sdk fork:     franchecol/cva6-sdk
cva6-sdk branch:   occamy-minimal-bootstrap
```

## Local Occamy Roadmap

Start with the
[Local Occamy Milestone Roadmap](docs/local-occamy-roadmap.md). It explains
what each milestone proves, how to reproduce it, what evidence counts as
success, and which detailed document to read.

```text
┌─────┬──────────────────────────────────────────────┬───────────┐
│ M0  │ CVA6 wakes Snitch and receives completion   │ completed │
│ M1  │ Snitch changes host-visible shared memory   │ completed │
│ M2  │ Runtime, DMA, barriers, FP AXPY              │ completed │
│ M3a │ Live mailbox manager calls a device target  │ completed │
│ M3b │ Linux/OpenMP launches replay via Verilator  │ frozen    │
│ M4  │ Real FPGA map(tofrom) proof                  │ next      │
└─────┴──────────────────────────────────────────────┴───────────┘
```

M3 has two explicit layers. M3a is the deterministic mailbox-runtime test run
by `bootstrap-local-occamy-m3.sh`. M3b is the broader freeze where qemu reaches
the Occamy OpenMP plugin and all captured launches replay through Verilator.

The M3b freeze is not a continuously connected qemu-to-Verilator device model.
It proves that the HeroSDK/OpenMP cva6/occamy stack builds, qemu reaches the
plugin, all 16 captured OpenMP launches can be gated on Verilator replay, and
the five `map(tofrom)` launches receive replay-derived W32 copybacks.

The next intended step is FPGA bring-up with the tiny
`apps/omp/basic/map_tofrom_u32` probe, not further expansion of the replay
bridge.

## Start Here

On a stock Arch Linux install:

```bash
sudo pacman -Syu
sudo pacman -S --needed base-devel git python ripgrep bc dtc verilator bender riscv64-elf-gcc qemu-user
```

On Debian/Ubuntu/Mint and similar distributions, install equivalent tools and
use the same repo-side commands.

Fresh checkout and M0:

```bash
git clone https://github.com/franchecol/hero-tools.git
cd hero-tools
git switch occamy-minimal-bootstrap
./scripts/bootstrap-local-occamy-minimal.sh
```

For M2, M3a, and M3b, initialize the HeroSDK submodules:

```bash
git submodule update --init --recursive cva6-sdk toolchain/llvm-project sw/libhero/vendor/o1heap
```

Canonical deterministic milestone commands:

```bash
./scripts/bootstrap-local-occamy-minimal.sh
./scripts/bootstrap-local-occamy-m1.sh
./scripts/bootstrap-local-occamy-m2.sh
./scripts/bootstrap-local-occamy-m3.sh
```

The broader M3b frozen run is:

```bash
./scripts/run-local-occamy-openmp-replay-bridge.sh --all
```

Current reproducibility scope:

```text
M0/M1  pinned simulator environment and source checks
M2     pinned generated inputs, source trees, compiler, and loadable artifacts
M3a    pinned source trees, compiler, artifacts, and trace behavior
M3b    matching cva6-sdk source is pinned; clean-machine revalidation remains
```

## Find The Right Document

- Start with the [M0-through-M4 roadmap](docs/local-occamy-roadmap.md) for the incremental story.
- Use the [M0 Manual Replay](docs/local-occamy-m0-manual-replay.md) to reproduce M0 phase by phase.
- Use the [M1 Manual Replay](docs/local-occamy-m1-manual-replay.md) for the shared-memory roundtrip.
- Use the [M2 Manual Replay](docs/local-occamy-m2-manual-replay.md) for deterministic AXPY.
- Use the [M3a Manual Replay](docs/local-occamy-m3-manual-replay.md) for the live mailbox runtime.
- Use the [M3b OpenMP Replay Freeze](docs/local-occamy-m3b-openmp-freeze.md) for qemu/replay evidence.
- Use the [M4 FPGA Bring-Up Plan](docs/local-occamy-m4-fpga-bringup.md) to continue on VCU128 hardware.
- Use the [M0 Bootstrap And Runner](docs/local-occamy-m0-bootstrap-runner.md) to understand the automation.
- Use the [M0 Deep Dive](docs/local-occamy-m0-deep-dive.md) for architecture and debugging detail.
- Use the [Device-Side Snitch Comparison](docs/local-occamy-device-side-snitch-comparison.md) to compare standalone Snitch with Occamy.

The old root paths `LOCAL_OCCAMY.md` and `LOCAL_OCCAMY_FPGA_BRINGUP.md` remain
as short compatibility pointers. The maintained runbooks are under `docs/`.

## Upstream HeroSDK

HeroSDK is an open-research software development kit for heterogeneous RISC-V
platforms. It enables accelerated Linux userspace applications using OpenMP
target for programmable multi-core clusters. The upstream project currently
targets Carfield and Occamy.

HeroSDK continues the Hero and HeroV2 line, but those projects are not yet
compatible with this repository. Use the original Hero repository for work
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
