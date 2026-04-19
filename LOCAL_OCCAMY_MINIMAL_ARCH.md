# Stock Arch Linux Quickstart For The Minimal Occamy Run

Status: validated against this local bootstrap flow on 2026-04-18.

This note is for the reduced local proof only.

It does not cover:

- the full HeroSDK LLVM/OpenMP toolchain build
- `make hero-cva6-sdk-all`
- FPGA bitstreams
- Linux image generation

It only covers the minimal local Verilator path driven by:

- `scripts/bootstrap-local-occamy-minimal.sh`
- `scripts/run-local-occamy-minimal.sh`

If your checkout does not contain those scripts, you are not on the local
branch/commit that added this reduced flow.

## What You Need On A Fresh Arch Install

Install the required packages:

```bash
sudo pacman -Syu
sudo pacman -S --needed base-devel git python ripgrep bc dtc verilator bender riscv64-elf-gcc
```

Why those packages are enough:

```text
base-devel      -> host-side build tools used by the Verilator C++ build
git             -> clone hero-tools and clone platforms/occamy from the bootstrap
python          -> venv + local Python dependency install used by the bootstrap
ripgrep         -> provides rg, which the runner uses for trace checks
bc              -> required by the simulator build
dtc             -> provides the device-tree compiler used by the simulator flow
verilator       -> RTL-to-C++ simulator frontend
bender          -> hardware dependency manager used by Occamy
riscv64-elf-gcc -> bare-metal RISC-V toolchain; pulls in riscv64-elf-binutils
```

Notes:

- `base-devel` is important here. The script itself checks `make`, but the
  Verilator-generated build also needs a normal host compiler and binutils.
- You do not need `python-pip` for this path. The bootstrap uses a local venv
  and installs the Python modules into that environment.
- You do not need a built `cva6-sdk` for this reduced proof.
- The script is not Arch-only. This guide is Arch-only. On Debian/Ubuntu/Mint,
  install equivalent tools and keep the same repo-side command.

## Clone The Repo

If you do not already have the checkout:

```bash
git clone https://github.com/pulp-platform/hero-tools.git
cd hero-tools
```

This quickstart assumes the checkout already contains:

- `scripts/bootstrap-local-occamy-minimal.sh`
- `scripts/run-local-occamy-minimal.sh`

Quick sanity check:

```bash
test -x scripts/bootstrap-local-occamy-minimal.sh
test -x scripts/run-local-occamy-minimal.sh
```

If either command fails, your checkout does not yet include the reduced local
flow described here.

## Run It

From the repo root:

```bash
./scripts/bootstrap-local-occamy-minimal.sh
```

That single command will:

- clone `platforms/occamy` on branch `ck/fpga2` if it is missing
- patch the local simulator Makefile for the current Verilator build
- create the tiny `minimal_irq` Snitch payload if it is missing
- create `.venv-occamy`
- install the required Python modules into that venv
- create `~/bin/riscv64-unknown-elf-*` compatibility symlinks from Arch's
  `riscv64-elf-*` tool names when needed
- build the reduced single-cluster simulator
- build the host and device binaries
- run the simulation
- verify the traces

Cross-distro override examples:

```bash
RISCV_TOOL_PREFIX=riscv64-none-elf- ./scripts/bootstrap-local-occamy-minimal.sh
VERILATOR_ROOT=/opt/verilator/share/verilator ./scripts/bootstrap-local-occamy-minimal.sh
```

## What Success Looks Like

The end of the run should contain:

```text
[occamy-minimal] success
[occamy-minimal] host ELF: .../offload-minimal_irq.elf
[occamy-minimal] device binary: .../minimal_irq.bin
[occamy-minimal] host trace: .../trace_hart_00.dasm
[occamy-minimal] device trace: .../logs/trace_hart_00001.dasm
```

The main output artifacts are:

- `platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf`
- `platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin`
- `platforms/occamy/target/sim/trace_hart_00.dasm`
- `platforms/occamy/target/sim/logs/trace_hart_00001.dasm`

## Disk Budget

Observed sizes on this machine after a successful run:

```text
.venv-occamy                         ≈  31M
platforms/occamy                    ≈ 218M
platforms/occamy/target/sim/work-vlt ≈ 2.0G
```

Practical recommendation:

- keep at least 4 GiB free for the reduced path
- 6 GiB free is safer if you want room for rebuilds and package downloads

## Common Failure Cases

If the script says a command is missing:

- install the package from the `pacman -S --needed ...` line above

If it says the minimal payload is missing:

- run `./scripts/bootstrap-local-occamy-minimal.sh`, not the rerun script

If it says the existing `platforms/occamy` checkout has the wrong origin or
branch:

- fix that checkout manually or remove it and let the bootstrap clone it again

If your checkout does not have the bootstrap script at all:

- you are on plain upstream `hero-tools`, not the locally extended checkout

## After The First Run

For faster reruns, use:

```bash
./scripts/run-local-occamy-minimal.sh
```

That rerun path assumes:

- `platforms/occamy` is already present
- the local simulator patch is already applied
- the `minimal_irq` app already exists

For the broader context and manual build details, see:

- `LOCAL_OCCAMY_MINIMAL.md`
