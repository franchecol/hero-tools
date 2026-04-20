# Local Occamy Minimal Heterogeneous Runbook

Status: validated on this machine through `M2` on 2026-04-20.

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

Optional M1 data-path rerun:

```bash
./scripts/run-local-occamy-minimal.sh roundtrip
```

Optional M2 reduced offload rerun:

```bash
source scripts/setenv.sh
make hero-tc-llvm-axpy
./scripts/run-local-occamy-minimal.sh axpy
```

It does not try to cover a full user-facing HeroSDK OpenMP target application
or the broader Linux/FPGA bring-up flow.
It only covers:

- reduced `occamy` configuration
- open-source Verilator simulator
- host-side CVA6 apps for a control-path proof and a tiny data-path proof
- the existing Occamy `offload` host path for a reduced runtime-shaped proof
- tiny RV32 device payloads on Snitch
- host <- device completion via software interrupt
- one minimal shared-memory roundtrip
- one reduced `axpy` offload proof using the HeroSDK RV32 LLVM device toolchain

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
- roundtrip host ELF:
  `platforms/occamy/target/sim/sw/host/apps/roundtrip/build/roundtrip.elf`
- roundtrip device binary:
  `platforms/occamy/target/sim/sw/device/apps/roundtrip/build/roundtrip.bin`
- `axpy` host ELF:
  `platforms/occamy/target/sim/sw/host/apps/offload/build/offload-axpy.elf`
- `axpy` device binary:
  `platforms/occamy/target/sim/sw/device/apps/blas/axpy/build/axpy.bin`

Required files provided by the matching Occamy fork branch:

- `platforms/occamy/target/sim/sw/device/apps/minimal_irq/`
- `platforms/occamy/target/sim/sw/device/apps/roundtrip/`
- `platforms/occamy/target/sim/sw/host/apps/roundtrip/`

Required simulator compatibility fix provided by that Occamy branch:

- `platforms/occamy/target/sim/Makefile`
  Adds `verilated_timing.o` and `verilated_threads.o` to the Verilator link.
- `platforms/occamy/target/sim/sw/device/toolchain.mk`
  Points the reduced `axpy` path at the `rv32imafd-ilp32d` builtins directory.

## Branches

This local run used:

- `hero-tools`: `franchecol/hero-tools` branch `occamy-minimal-bootstrap`
- `platforms/occamy`: `franchecol/occamy` branch
  `occamy-minimal-bootstrap`

Notes:

- The generic docs still describe the broader FPGA/Linux bring-up path.
- This reduced Verilator proof does not require `make hero-cva6-sdk-all` or a
  locally built `cva6-sdk`.
- It still assumes you already cloned this `hero-tools` checkout.
- The bootstrap script clones `platforms/occamy` from the matching fork branch
  if it is missing, or checks that the existing checkout already matches it.
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

For the optional `axpy` proof, this machine also needed the reduced HeroSDK
RV32 LLVM toolchain and sysroot built with:

```bash
source scripts/setenv.sh
make hero-tc-llvm-axpy
```

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

For the optional `axpy` verification harness, the venv also needed:

```bash
pip install numpy pyelftools
```

## Environment Setup

Use this setup in every terminal used for the manual minimal path:

```bash
cd /home/ftv/builds/hero-tools
source .venv-occamy/bin/activate
export PATH=/home/ftv/bin:$PATH
```

For the optional `axpy` path, also load the HeroSDK environment:

```bash
source scripts/setenv.sh
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

## Run The Minimal Data-Path Roundtrip

This second proof stays in the same reduced single-cluster simulation, but it
verifies actual shared-memory exchange instead of only the interrupt handshake.

Build the device payload:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim/sw/device/apps/roundtrip
make clean
make
```

Build the host app:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim/sw/host/apps/roundtrip
make clean
make finalize-build
```

Run it:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/target/sim
./bin/occamy_top.vlt ./sw/host/apps/roundtrip/build/roundtrip.elf
```

Expected behavior:

- the simulator exits with code `0`
- useful status comes from the exit code and traces, not UART output

What it proves:

- the host initializes a 16-word buffer
- the host passes the shared buffer pointer through `comm_buffer.usr_data_ptr`
- the Snitch payload increments the 16 words in place
- the host validates the returned buffer before exiting

## Run The Reduced `axpy` Offload Proof

This third proof stays in the same reduced single-cluster simulation, but it
uses the existing Occamy `offload` host path together with the upstream
`device/apps/blas/axpy` workload and the reduced HeroSDK RV32 LLVM toolchain.

Build the reduced LLVM RV32 device toolchain pieces first:

```bash
cd /home/ftv/builds/hero-tools
source scripts/setenv.sh
make hero-tc-llvm-axpy
```

Then run the validated branch-local flow:

```bash
cd /home/ftv/builds/hero-tools
./scripts/run-local-occamy-minimal.sh axpy
```

What this run does:

- builds the reduced single-cluster simulator if needed
- builds the device runtime and math libraries required by `axpy`
- performs the host partial build to emit `origin.ld`
- builds `axpy.elf` and `axpy.bin`
- finalizes `offload-axpy.elf`
- runs the upstream `verify.py` harness against the simulator

Expected success lines:

```text
[occamy-minimal] success
[occamy-minimal] mode: axpy
[occamy-minimal] host ELF: .../offload-axpy.elf
[occamy-minimal] device binary: .../axpy.bin
```

What it proves:

- the reduced HeroSDK RV32 LLVM toolchain and sysroot build are usable here
- the existing Occamy offload packaging flow works in this reduced simulator
- the richer `axpy` device workload builds and links against the required
  runtime libraries
- the simulation reaches the verification harness successfully

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

For `axpy`, the main proof is different:

- the reduced flow emits both `offload-axpy.elf` and `axpy.bin`
- the upstream verification harness completes and the runner reports
  `[occamy-minimal] success`

## Known Good Smoke Tests

Three simple tests are currently useful:

- host-only boot/exit smoke:
  `platforms/occamy/target/sim/sw/host/apps/exit_only`
- minimal heterogeneous smoke:
  `platforms/occamy/target/sim/sw/host/apps/offload` +
  `platforms/occamy/target/sim/sw/device/apps/minimal_irq`
- reduced runtime-shaped smoke:
  `platforms/occamy/target/sim/sw/host/apps/offload` +
  `platforms/occamy/target/sim/sw/device/apps/blas/axpy`

## Known Bad Or Incomplete Paths

Current caveats in this checkout:

- `hello_world` built, but did not produce UART output and did not terminate in
  the expected way during earlier testing.
- the reduced HeroSDK RV32 LLVM toolchain and the `axpy` proof now work on this
  machine, but a real user-facing OpenMP target application is still unproven
  in this reduced branch flow.
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
