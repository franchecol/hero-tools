# Local Occamy Minimal Heterogeneous Runbook

Status: validated on this machine on 2026-04-18.

This note documents the smallest heterogeneous simulation path that was
actually proven in this checkout.

Stock Arch Linux setup guide:

- `LOCAL_OCCAMY_MINIMAL_ARCH.md`

One-command path for first-time local setup:

```bash
./scripts/bootstrap-local-occamy-minimal.sh
```

Fast rerun path after bootstrap:

```bash
./scripts/run-local-occamy-minimal.sh
```

It does not try to cover the full HeroSDK LLVM/OpenMP flow.
It only covers:

- reduced `occamy` configuration
- open-source Verilator simulator
- host-side `offload` app on CVA6
- tiny RV32 device payload on Snitch
- host <- device completion via software interrupt

## Scope

Proven end-to-end flow:

```text
CVA6 host ELF
  -> programs Snitch entry point
  -> wakes cluster
  -> waits for host software interrupt

Snitch device payload
  -> hart 1 writes CLINT host-MSIP
  -> all harts park in WFI

Simulator
  -> host resumes
  -> host reaches _exit and writes tohost
  -> simulation exits
```

Known-good artifacts:

- host ELF:
  `platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf`
- device binary:
  `platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin`

Supporting local files added in this checkout:

- `platforms/occamy/target/sim/sw/device/apps/minimal_irq/`

Local simulator patch already present in this checkout:

- `platforms/occamy/target/sim/Makefile`
  Adds `verilated_timing.o` and `verilated_threads.o` to the Verilator link.

## Branches

This local run used:

- `platforms/occamy` on branch `ck/fpga2`

Notes:

- The generic docs still describe the broader FPGA/Linux bring-up path.
- This reduced Verilator proof does not require `make hero-cva6-sdk-all` or a
  locally built `cva6-sdk`.
- It still assumes you already cloned this `hero-tools` checkout.
- The bootstrap script clones `platforms/occamy` for you if it is missing.
- The scripts are Linux-distro portable as long as equivalent tools exist in
  `PATH`; only the package-manager instructions are Arch-specific.

## Local Prerequisites

The following must exist on the machine:

- `git`
- `bc`
- `dtc`
- `verilator`
- `bender`
- a bare-metal RISC-V GNU toolchain
- Python 3 with `venv`

For a stock Arch Linux package-level setup, see:

- `LOCAL_OCCAMY_MINIMAL_ARCH.md`

This machine also needed compatibility symlinks because Arch provides
`riscv64-elf-*`, while this flow expects `riscv64-unknown-elf-*`.

Symlinks currently live in:

- `/home/ftv/bin`

Important examples:

- `/home/ftv/bin/riscv64-unknown-elf-gcc`
- `/home/ftv/bin/riscv64-unknown-elf-objcopy`
- `/home/ftv/bin/riscv64-unknown-elf-objdump`

Cross-distro notes:

- if your distro already provides `riscv64-unknown-elf-*`, the scripts use that
  directly
- if your distro provides `riscv64-elf-*`, the scripts map it automatically
- if your distro uses a different bare-metal prefix, run with:
  `RISCV_TOOL_PREFIX=<prefix> ./scripts/bootstrap-local-occamy-minimal.sh`
- if Verilator is installed outside the usual share path, run with:
  `VERILATOR_ROOT=/path/to/share/verilator ./scripts/bootstrap-local-occamy-minimal.sh`

## Python Environment

The Occamy generation flow needed a local virtual environment:

```bash
cd /home/ftv/builds/hero-tools
python -m venv .venv-occamy
source .venv-occamy/bin/activate
pip install hjson jsonref mako pyyaml tabulate jsonschema "setuptools<81"
```

Why the setuptools pin exists:

- the vendored `regtool.py` path still relies on `pkg_resources`

## Environment Setup

Use this setup in every terminal used for the manual minimal path:

```bash
cd /home/ftv/builds/hero-tools
source .venv-occamy/bin/activate
export PATH=/home/ftv/bin:$PATH
```

## Build The Reduced Occamy Simulator

Use the single-cluster config. The full config is too large for quick local RTL
iteration.

Generate the platform headers first:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim
make CFG_OVERRIDE=cfg/single-cluster.hjson VERIBLE_FMT=true all-headers
```

Build the Verilator simulator with the local compatibility overrides:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim
make CFG_OVERRIDE=cfg/single-cluster.hjson VERIBLE_FMT=true \
  VLT='verilator --timing -DASSERTS_OFF' \
  VERILATOR_ROOT=/usr/share/verilator \
  VLT_ROOT=/usr/share/verilator \
  CXXFLAGS='-include cstdint -fcoroutines' \
  bin/occamy_top.vlt
```

Notes:

- `VERIBLE_FMT=true` is a local workaround for missing `clang-format-10.0.1`
  or `verible-verilog-format`.
- `--timing` was required for the current Verilator build.
- `-include cstdint` was required with the current host GCC.
- `-fcoroutines` was needed for the simulator-side C++ build.
- the script now autodetects `VERILATOR_ROOT`, but you can still override it
  explicitly if your distro packages Verilator in a non-standard location

Expected output:

- `platforms/occamy/target/sim/bin/occamy_top.vlt`

## Build The Minimal Device Payload

The device payload is intentionally tiny. It does not use the full HeroSDK
device runtime. It only proves that a Snitch hart can execute and raise the
host software interrupt.

Build it with:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim/sw/device/apps/minimal_irq
make clean
make
```

What it does:

- reads `mhartid`
- only hart 1 performs the signal
- writes `1` to `0x04000000`
- parks in `wfi`

Why `-march=rv32im_zicsr` is used:

- GNU `as` rejects `csrr` without explicitly enabling `zicsr`

## Build The Host Offload ELF

The existing host app is reused:

- `platforms/occamy/target/sim/sw/host/apps/offload`

Build sequence:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim/sw/host/apps/offload
make clean
make DEVICE_APPS=minimal_irq
make finalize-build DEVICE_APPS=minimal_irq
```

What happens:

- the partial build creates `offload.part.elf`
- the build extracts the relocation address of `snitch_main`
- it writes that address into:
  `platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/origin.ld`
- the final build embeds `minimal_irq.bin` into the host ELF

Expected output:

- `platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf`

## Run The Minimal Heterogeneous Simulation

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim
./bin/occamy_top.vlt ./sw/host/apps/offload/build/offload-minimal_irq.elf
```

Expected behavior:

- no useful UART output
- simulator starts, logs hart traces, and exits cleanly

Files worth checking afterwards:

- `trace_hart_00.dasm`
- `logs/trace_hart_00001.dasm`
- `logs/trace_hart_00009.dasm`

## What To Verify

Host-side proof:

- `trace_hart_00.dasm` should show the host:
  - waiting for the Snitches
  - clearing the host software interrupt at `0x04000000`
  - reaching `_exit`
  - writing `tohost`

Device-side proof:

- `logs/trace_hart_00001.dasm` should show:
  - `csrr a0, mhartid`
  - branch selecting hart 1
  - `lui t1,0x4000`
  - `sw t2,0(t1)`
  - then repeated `wfi`

This is enough to say the host/device control path works.

## Known Good Smoke Tests

Two simple tests are currently useful:

- host-only boot/exit smoke:
  `platforms/occamy/target/sim/sw/host/apps/exit_only`
- minimal heterogeneous smoke:
  `platforms/occamy/target/sim/sw/host/apps/offload` +
  `platforms/occamy/target/sim/sw/device/apps/minimal_irq`

## Known Bad Or Incomplete Paths

Current caveats in this checkout:

- `hello_world` built, but did not produce UART output and did not terminate in
  the expected way during earlier testing.
- The full HeroSDK LLVM/OpenMP toolchain path is not stabilized on this
  machine yet.
- The repo docs are not enough by themselves for modern local bring-up on this
  machine; they assume older pinned tools and a more curated environment.

## Why This Note Exists

The upstream docs explain the architecture, but they do not provide a clean,
local, simulator-only runbook for:

- modern Verilator
- Arch-style tool naming
- current Python packaging behavior
- the smallest heterogeneous proof

This file is the shortest path that was actually validated here.
