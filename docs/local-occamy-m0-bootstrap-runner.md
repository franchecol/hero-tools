# Local Occamy M0 Bootstrap And Runner

This note explains the two scripts used by the local M0 flow and how they set
up Occamy to simulate a reduced system with one Snitch cluster.

Use this document when you want to understand the automation and Makefile
handoffs. To type the phases manually, use the
[M0 Manual Replay](local-occamy-m0-manual-replay.md). For the complete milestone
progression, start with the
[Local Occamy Milestone Roadmap](local-occamy-roadmap.md).

The broader architecture and debugging explanation is in the
[M0 Deep Dive](local-occamy-m0-deep-dive.md).

This file focuses on one narrower question:

```text
When I run ./scripts/bootstrap-local-occamy-minimal.sh, what actually happens?
```

The short answer is:

```text
bootstrap-local-occamy-minimal.sh
  makes sure the right Occamy fork checkout exists under platforms/occamy,
  verifies that the local branch contains the expected M0 files, then execs
  the runner.

run-local-occamy-minimal.sh
  prepares the local build environment, selects the M0 app, builds reduced
  Occamy with cfg/single-cluster.hjson, builds the host/device binaries,
  runs Verilator, and checks the traces.
```

## 1. Why There Are Two Scripts

The two scripts have different responsibilities.

```text
┌─────────────────────────────────────────────────────────────┐
│ scripts/bootstrap-local-occamy-minimal.sh                   │
├─────────────────────────────────────────────────────────────┤
│ Source checkout setup and validation                        │
│                                                             │
│ - Are we in hero-tools?                                     │
│ - Is the runner script present?                             │
│ - Is platforms/occamy present?                              │
│ - If not, clone the expected Occamy fork branch.             │
│ - If yes, check the remote and branch.                       │
│ - Check that required M0/M1 Occamy-side files exist.         │
│ - Check Verilator compatibility edits exist.                 │
│ - Replace itself with the runner script.                     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ scripts/run-local-occamy-minimal.sh                         │
├─────────────────────────────────────────────────────────────┤
│ Build, run, and verification flow                           │
│                                                             │
│ - Select app mode: minimal_irq, roundtrip, axpy, mailbox.    │
│ - Create/reuse Python venv.                                 │
│ - Resolve Verilator root.                                   │
│ - Resolve RISC-V toolchain prefix.                          │
│ - Build reduced Occamy headers.                             │
│ - Build reduced Verilator simulator.                        │
│ - Build selected Snitch device payload.                     │
│ - Build CVA6 host ELF embedding that payload.                │
│ - Run the simulator.                                        │
│ - Verify traces.                                            │
└─────────────────────────────────────────────────────────────┘
```

The split exists because `platforms/occamy` is not just a normal tracked folder
inside this `hero-tools` branch.  It is a separate Occamy checkout.  The
bootstrap script makes that external checkout reproducible.  The runner script
assumes that checkout is correct and then performs the actual simulation work.

## 2. Entry Point

The normal M0 command is:

```bash
./scripts/bootstrap-local-occamy-minimal.sh
```

That command eventually runs:

```bash
./scripts/run-local-occamy-minimal.sh minimal_irq
```

The `minimal_irq` argument is optional because it is the runner default:

```bash
./scripts/run-local-occamy-minimal.sh
```

is equivalent to:

```bash
./scripts/run-local-occamy-minimal.sh minimal_irq
```

## 3. Bootstrap Script

The bootstrap script is:

```text
scripts/bootstrap-local-occamy-minimal.sh
```

The important variables are:

```bash
ROOT_DIR=...
OCCAMY_DIR="${ROOT_DIR}/platforms/occamy"
OCCAMY_URL="${OCCAMY_URL:-https://github.com/franchecol/occamy.git}"
OCCAMY_BRANCH="${OCCAMY_BRANCH:-occamy-minimal-bootstrap}"
RUNNER="${ROOT_DIR}/scripts/run-local-occamy-minimal.sh"
SIM_MAKEFILE="${OCCAMY_DIR}/target/sim/Makefile"
```

Meaning:

```text
ROOT_DIR
  The hero-tools repository root.

OCCAMY_DIR
  The expected Occamy checkout location inside hero-tools.

OCCAMY_URL
  The expected Occamy fork.  This can be overridden by environment variable,
  but defaults to franchecol/occamy.

OCCAMY_BRANCH
  The expected Occamy branch.  This can be overridden by environment variable,
  but defaults to occamy-minimal-bootstrap.

RUNNER
  The script that performs the actual build/run/verify flow.

SIM_MAKEFILE
  The Occamy simulator Makefile that must contain the local Verilator fixes.
```

### 3.1 Required Occamy Files

The bootstrap script checks for these files:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/Makefile
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
platforms/occamy/target/sim/sw/device/apps/roundtrip/Makefile
platforms/occamy/target/sim/sw/device/apps/roundtrip/src/roundtrip.S
platforms/occamy/target/sim/sw/host/apps/roundtrip/Makefile
platforms/occamy/target/sim/sw/host/apps/roundtrip/src/roundtrip.c
```

For M0, the most important files are:

```text
target/sim/sw/device/apps/minimal_irq/Makefile
target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
```

The roundtrip files are checked too because the same bootstrap supports M1.

### 3.2 `ensure_checkout`

The first real guard is conceptually:

```bash
[[ -d "${ROOT_DIR}/.git" ]] || die "bootstrap must run from a hero-tools checkout"
[[ -x "${RUNNER}" ]] || die "missing runner script: ${RUNNER}"
```

This prevents a misleading failure later.  If the script is copied somewhere
else or run without the rest of the repo, it fails immediately.

### 3.3 `ensure_occamy_checkout`

This is the main bootstrap function.

If `platforms/occamy/.git` is missing, the script runs:

```bash
git clone --branch "${OCCAMY_BRANCH}" --single-branch \
  "${OCCAMY_URL}" "${OCCAMY_DIR}"
```

With defaults, that means:

```bash
git clone --branch occamy-minimal-bootstrap --single-branch \
  https://github.com/franchecol/occamy.git \
  platforms/occamy
```

If `platforms/occamy` already exists, the script does not blindly overwrite it.
It checks:

```text
1. Does the checkout have origin or fork remote?
2. Does either remote point to the expected Occamy fork?
3. Is the current branch occamy-minimal-bootstrap?
```

This is important because a stale or upstream Occamy checkout can look almost
right but fail later in confusing ways.  The bootstrap catches that early.

### 3.4 Remote Normalization

The script accepts common GitHub URL forms:

```text
https://github.com/franchecol/occamy.git
http://github.com/franchecol/occamy.git
git@github.com:franchecol/occamy.git
ssh://git@github.com/franchecol/occamy.git
```

It normalizes them before comparing.  This avoids rejecting a correct checkout
just because the remote uses SSH instead of HTTPS.

### 3.5 `require_occamy_branch_content`

After the checkout exists and branch/remotes look correct, the bootstrap
validates actual content.

First it checks the simulator Makefile:

```text
platforms/occamy/target/sim/Makefile
```

Then it requires these two strings:

```text
verilated_timing.o
verilated_threads.o
```

Those are local Verilator compatibility requirements.  If they are missing, it
usually means the Occamy checkout is not the matching fork branch.

Then the script checks every required M0/M1 file listed above.

### 3.6 Final `exec`

At the end, bootstrap does:

```bash
exec "${RUNNER}" "$@"
```

This replaces the bootstrap process with the runner process.

That detail matters:

```text
bootstrap does not call the runner and then continue.
bootstrap becomes the runner.
```

So all arguments are forwarded.

Examples:

```bash
./scripts/bootstrap-local-occamy-minimal.sh
```

runs the default M0 mode:

```bash
./scripts/run-local-occamy-minimal.sh minimal_irq
```

And:

```bash
./scripts/bootstrap-local-occamy-minimal.sh roundtrip
```

becomes:

```bash
./scripts/run-local-occamy-minimal.sh roundtrip
```

## 4. Runner Script

The runner script is:

```text
scripts/run-local-occamy-minimal.sh
```

This is the actual local flow.

The important top-level variables are:

```bash
SIM_DIR="${ROOT_DIR}/platforms/occamy/target/sim"
VENV_DIR="${ROOT_DIR}/.venv-occamy"
USER_BIN_DIR="${HOME}/bin"
HERO_INSTALL_DIR="${HERO_INSTALL:-${ROOT_DIR}/install}"
CANONICAL_RISCV_PREFIX="riscv64-unknown-elf-"
APP_MODE="${1:-minimal_irq}"
```

Meaning:

```text
SIM_DIR
  Occamy simulator directory.

VENV_DIR
  Local Python virtual environment for Occamy generation scripts.

USER_BIN_DIR
  Used for RISC-V toolchain compatibility symlinks.

HERO_INSTALL_DIR
  HeroSDK install directory, only needed for richer modes like axpy and
  omp_mailbox.

CANONICAL_RISCV_PREFIX
  Tool prefix expected by the Occamy Makefiles.

APP_MODE
  Selected local proof.  Defaults to minimal_irq, which is M0.
```

## 5. Runner Modes

The runner supports several modes:

```text
minimal_irq
  M0.  CVA6 wakes Snitch.  Snitch writes host CLINT MSIP.  Host exits.

roundtrip
  M1.  Snitch increments a 16-word host buffer and host validates it.

axpy
  M2.  Reduced runtime-shaped AXPY proof.

omp_mailbox
  M3a mailbox/runtime-shaped proof in Verilator.
```

For M0, the selected mode is `minimal_irq`.

The M0 paths are:

```text
DEVICE_APP_DIR
  platforms/occamy/target/sim/sw/device/apps/minimal_irq

HOST_APP_DIR
  platforms/occamy/target/sim/sw/host/apps/offload

HOST_ELF
  platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf

DEVICE_BIN
  platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin

DEVICE_SYMBOL_ELF
  platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.elf
```

## 6. Runner Main Flow

The runner `main()` flow is:

```text
1. need_cmd python
2. need_cmd make
3. need_cmd rg
4. need_cmd bender
5. need_cmd verilator
6. need_cmd dtc
7. need_cmd bc
8. need_cmd gcc, g++, c++, ar, ld
9. configure_mode
10. check SIM_DIR
11. check selected device Makefile
12. ensure_venv
13. ensure_hero_device_toolchain
14. resolve_verilator_root
15. ensure_riscv_aliases
16. verify_local_patch
17. build_simulator
18. build_selected_payload
19. run_simulation
20. verify_traces
21. print success and artifact paths
```

For M0, `ensure_hero_device_toolchain` returns immediately because M0 does not
need the HeroSDK LLVM RV32 toolchain.  It uses the bare-metal RISC-V GCC path.

## 7. Python Environment

Occamy generation uses Python packages.  The runner creates:

```text
.venv-occamy
```

Then it checks/imports:

```text
hjson
jsonref
mako
yaml
tabulate
jsonschema
pkg_resources
```

If they are missing, it installs:

```bash
python -m pip install hjson jsonref mako pyyaml tabulate jsonschema "setuptools<81"
```

This venv is local to the repo and should not be committed.

## 8. Verilator Root

The runner resolves `VERILATOR_ROOT` because Occamy's simulator build needs
Verilator support sources such as:

```text
verilated.cpp
verilated_dpi.cpp
verilated_vcd_c.cpp
verilated_timing.cpp
verilated_threads.cpp
```

The runner accepts an existing environment variable:

```bash
VERILATOR_ROOT=/path/to/share/verilator
```

If it is not set, it tries to infer it from:

```bash
verilator -V
```

or common install paths such as:

```text
/usr/share/verilator
/usr/local/share/verilator
```

Then it exports:

```bash
VERILATOR_ROOT=...
VLT_ROOT="${VERILATOR_ROOT}"
```

## 9. RISC-V Toolchain Prefix

Occamy's Makefiles expect tools named:

```text
riscv64-unknown-elf-gcc
riscv64-unknown-elf-objcopy
riscv64-unknown-elf-objdump
riscv64-unknown-elf-readelf
```

But some distros, including Arch-style setups, may provide:

```text
riscv64-elf-gcc
```

The runner handles this by searching these prefixes:

```text
riscv64-unknown-elf-
riscv64-elf-
riscv64-none-elf-
```

If the available prefix is not `riscv64-unknown-elf-`, it creates symlinks in:

```text
~/bin
```

Example:

```text
~/bin/riscv64-unknown-elf-gcc -> /usr/bin/riscv64-elf-gcc
```

Then it prepends `~/bin` to `PATH`.

This is why the script can work across distros without patching Occamy's
Makefiles for every package naming convention.

## 10. Verilator Compatibility Check

The runner checks the Occamy simulator Makefile for:

```text
verilated_timing.o
verilated_threads.o
```

This mirrors the bootstrap check.  The duplication is intentional:

```text
bootstrap catches a bad Occamy checkout before setup
runner catches a bad Occamy checkout even if run directly
```

If someone skips bootstrap and runs:

```bash
./scripts/run-local-occamy-minimal.sh
```

the runner still protects itself.

## 11. How One Snitch Cluster Is Selected

The runner selects the reduced Occamy configuration in `build_simulator()`:

```bash
make -C "${SIM_DIR}" \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  all-headers

make -C "${SIM_DIR}" \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  VLT='verilator --timing -DASSERTS_OFF' \
  VERILATOR_ROOT="${VERILATOR_ROOT}" \
  VLT_ROOT="${VLT_ROOT}" \
  CXXFLAGS='-include cstdint -fcoroutines' \
  bin/occamy_top.vlt
```

The important part is:

```text
CFG_OVERRIDE=cfg/single-cluster.hjson
```

That points Occamy's generation/build flow at:

```text
platforms/occamy/target/sim/cfg/single-cluster.hjson
```

The key settings are:

```hjson
nr_s1_quadrant: 1,
s1_quadrant: {
  nr_clusters: 1,
}
```

Meaning:

```text
nr_s1_quadrant: 1
  Generate one S1 quadrant.

s1_quadrant.nr_clusters: 1
  Put one Snitch cluster in that quadrant.
```

This does not mean one Snitch core.  It means one Snitch cluster.  The cluster
still contains multiple harts/cores according to the cluster template.  In M0,
the device payload allows only hart 1 to perform the completion write, while
the other harts park.

The config also sets the cluster base properties:

```hjson
cluster: {
  name: "occamy_cluster"
  boot_addr: 4096, // 0x1000
  cluster_base_addr: 268435456, // 0x10000000
  cluster_base_offset: 262144 // 0x40000
  cluster_base_hartid: 1,
  tcdm: {
    size: 128, // 128 kiB
    banks: 32,
  },
}
```

Important meanings:

```text
boot_addr: 0x1000
  Default cluster boot address used by the Snitch-side boot path.

cluster_base_addr: 0x10000000
  Base address for cluster-local memory/peripheral address space.

cluster_base_offset: 0x40000
  Offset that would separate clusters if more clusters existed.

cluster_base_hartid: 1
  Host CVA6 is hart 0; Snitch cluster harts start at hart ID 1.

tcdm.size: 128 KiB
  Local tightly coupled data memory size for the cluster.
```

So the one-cluster setup is not done by manually deleting RTL.  It is done by
feeding a smaller HJSON configuration to Occamy's generator and build flow.

## 12. What `all-headers` Does

The first simulator build command is:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  all-headers
```

This generates the software-visible headers for the selected Occamy config.
Those include files such as:

```text
platforms/occamy/target/sim/sw/shared/platform/generated/occamy_base_addr.h
platforms/occamy/target/sim/sw/shared/platform/generated/occamy_cfg.h
platforms/occamy/target/sim/sw/shared/platform/generated/occamy_soc_ctrl.h
platforms/occamy/target/sim/sw/shared/platform/generated/clint.h
platforms/occamy/target/sim/sw/shared/platform/generated/snitch_cluster_peripheral.h
```

These headers are what let host code write symbolic helper functions like:

```c
*soc_ctrl_scratch_ptr(1) = (uintptr_t)snitch_main;
*(cluster_clint_set_ptr(cluster_id)) = 511;
*clint_msip_ptr(0) = 0;
```

instead of hardcoding every register offset by hand.

## 13. What `bin/occamy_top.vlt` Build Does

The second simulator build command is:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  VLT='verilator --timing -DASSERTS_OFF' \
  VERILATOR_ROOT="${VERILATOR_ROOT}" \
  VLT_ROOT="${VLT_ROOT}" \
  CXXFLAGS='-include cstdint -fcoroutines' \
  bin/occamy_top.vlt
```

This builds the executable Verilator model:

```text
platforms/occamy/target/sim/bin/occamy_top.vlt
```

Conceptually:

```text
single-cluster.hjson
  ↓
Occamy generator and register generators
  ↓
generated RTL under target/sim/src/
  ↓
Bender source resolution
  ↓
Verilator C++ model generation
  ↓
C++ compilation and linking
  ↓
bin/occamy_top.vlt
```

The C++ flags matter because the current Verilator-generated model needs:

```text
-include cstdint
-fcoroutines
```

The Verilator command matters because the current flow needs:

```text
--timing
-DASSERTS_OFF
```

## 14. Building The M0 Device Payload

After the simulator is available, the runner builds the selected payload.

For M0:

```bash
make -C platforms/occamy/target/sim/sw/device/apps/minimal_irq clean
make -C platforms/occamy/target/sim/sw/device/apps/minimal_irq all
```

The device Makefile builds:

```text
minimal_irq.elf
minimal_irq.bin
minimal_irq.dump
```

The source is:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
```

The payload is tiny:

```asm
csrr    a0, mhartid
li      t0, 1
bne     a0, t0, park

li      t1, 0x04000000
li      t2, 1
sw      t2, 0(t1)
fence   iorw, iorw

park:
  wfi
  j park
```

Meaning:

```text
Only Snitch hart 1 writes 1 to 0x04000000.
0x04000000 is the global CLINT MSIP register for the CVA6 host.
That write raises a host software interrupt.
All harts then park in WFI.
```

## 15. Building The M0 Host ELF

The M0 host app directory is:

```text
platforms/occamy/target/sim/sw/host/apps/offload
```

The runner runs:

```bash
make -C "${HOST_APP_DIR}" DEVICE_APPS=minimal_irq
make -C "${HOST_APP_DIR}" finalize-build DEVICE_APPS=minimal_irq
```

The host source is:

```text
platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
```

Its control flow is:

```c
reset_and_ungate_quadrants();
deisolate_all();
enable_sw_interrupts();
program_snitches();
asm volatile("" ::: "memory");
wakeup_snitches_cl();
wait_snitches_done();
mcycle();
```

The host build embeds the device binary into the host ELF.  The final M0 host
artifact is:

```text
platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf
```

This host ELF contains:

```text
CVA6 host program
startup code
tohost exit path
embedded Snitch minimal_irq binary
```

## 16. Why The Host Embeds The Device Binary

M0 is bare-metal.  There is no Linux filesystem, no dynamic loader, and no
driver loading a device image at runtime.

Instead:

```text
1. Device app builds minimal_irq.bin.
2. Host build embeds minimal_irq.bin into a .devicebin section.
3. The embedded device code gets the symbol name snitch_main.
4. Host code writes snitch_main into Occamy scratch register 1.
5. Snitch boot/wakeup path jumps to that address.
```

This is why M0 can be small and deterministic.

## 17. Running The Simulation

The runner executes:

```bash
cd platforms/occamy/target/sim
bin/occamy_top.vlt sw/host/apps/offload/build/offload-minimal_irq.elf
```

Before running, it removes old logs:

```bash
rm -f uart0.log trace_hart_00.dasm
rm -f logs/trace_hart_0000*.dasm
```

That prevents stale traces from making a broken run look successful.

The simulator loads the host ELF.  The CVA6 host starts executing.  The host
then wakes the Snitch cluster.  The Snitch payload interrupts the host.  The
host clears the interrupt and writes to `tohost`, ending the simulation.

## 18. Trace Verification

The runner verifies M0 with traces.

The host trace is:

```text
platforms/occamy/target/sim/trace_hart_00.dasm
```

The Snitch hart 1 trace is:

```text
platforms/occamy/target/sim/logs/trace_hart_00001.dasm
```

For `minimal_irq`, the runner requires:

```text
device trace:
  0x80000524 ... 00732023

host trace:
  0x80000464 ... 04000737
  0x80000068 ... 00a2a023
```

Interpretation:

```text
0x80000524 ... 00732023
  Snitch executed the store to 0x04000000.
  This raises the host software interrupt.

0x80000464 ... 04000737
  Host reached the interrupt clear path.

0x80000068 ... 00a2a023
  Host wrote to tohost.
  The simulator exited cleanly.
```

This is why the runner is stronger than a plain shell script that only checks
exit code.  It checks that the intended heterogeneous path actually happened.

## 19. Full M0 Flow

The full flow is:

```text
User
  │
  │ ./scripts/bootstrap-local-occamy-minimal.sh
  ▼
Bootstrap script
  │
  ├─ checks hero-tools checkout
  ├─ checks runner exists
  ├─ ensures platforms/occamy exists
  ├─ clones franchecol/occamy if needed
  ├─ checks Occamy branch and remote
  ├─ checks required Occamy-side files
  ├─ checks Verilator compatibility edits
  │
  │ exec scripts/run-local-occamy-minimal.sh
  ▼
Runner script
  │
  ├─ selects APP_MODE=minimal_irq
  ├─ creates .venv-occamy if needed
  ├─ installs Python generator deps if needed
  ├─ resolves VERILATOR_ROOT
  ├─ resolves RISC-V toolchain prefix
  ├─ builds headers with cfg/single-cluster.hjson
  ├─ builds bin/occamy_top.vlt
  ├─ builds minimal_irq.bin
  ├─ builds offload-minimal_irq.elf
  ├─ runs occamy_top.vlt offload-minimal_irq.elf
  ├─ verifies host/device traces
  │
  ▼
Success
```

The hardware/software effect is:

```text
CVA6 host starts
  ↓
host resets/ungates/de-isolates quadrant
  ↓
host writes snitch_main to SoC scratch register 1
  ↓
host writes &comm_buffer to SoC scratch register 2
  ↓
host writes 0x1ff to cluster CLINT_SET
  ↓
Snitch cluster wakes
  ↓
Snitch hart 1 executes minimal_irq.S
  ↓
Snitch hart 1 writes 1 to 0x04000000
  ↓
global CLINT sets host MSIP
  ↓
CVA6 host wakes from WFI
  ↓
host clears MSIP
  ↓
host writes tohost
  ↓
simulation exits
```

## 20. What Is Local And Generated

Source files that matter:

```text
scripts/bootstrap-local-occamy-minimal.sh
scripts/run-local-occamy-minimal.sh
platforms/occamy/target/sim/cfg/single-cluster.hjson
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
platforms/occamy/target/sim/sw/host/runtime/host.c
platforms/occamy/target/sim/sw/host/runtime/start.S
```

Generated/local artifacts:

```text
.venv-occamy/
platforms/occamy/target/sim/bin/occamy_top.vlt
platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/
platforms/occamy/target/sim/sw/host/apps/offload/build/
platforms/occamy/target/sim/trace_hart_00.dasm
platforms/occamy/target/sim/logs/trace_hart_00001.dasm
platforms/occamy/target/sim/sim.vcd
```

These generated artifacts should not be committed.

## 21. Why This Is Still M0, Not HeroSDK Offload

Even though the scripts live in `hero-tools`, M0 does not use OpenMP target
offload.

M0 is:

```text
CVA6 bare-metal host ELF
embedded Snitch bare-metal binary
MMIO scratch registers
cluster interrupt register
global CLINT software interrupt
trace-verified simulator exit
```

HeroSDK/OpenMP comes later, when the stack adds:

```text
Linux host process
OpenMP target runtime
libomptarget plugin
LibHero
kernel driver
mmap/ioctl
mailboxes
target launch packets
copyback behavior
```

So the scripts are valuable because they isolate the lowest-level Occamy
integration question:

```text
Can a CVA6 host in a reduced Occamy simulation wake a Snitch cluster and receive
a completion interrupt?
```

M0 answers that question with a small, repeatable, trace-checked flow.

## 22. Debugging Checklist

If the bootstrap fails:

```text
Check whether platforms/occamy exists.
Check git -C platforms/occamy remote -v.
Check git -C platforms/occamy branch --show-current.
Check that the branch is occamy-minimal-bootstrap.
Check that target/sim/sw/device/apps/minimal_irq exists.
Check that target/sim/Makefile contains verilated_timing.o and
verilated_threads.o.
```

If the runner fails before building:

```text
Check required commands:
  python
  make
  rg
  bender
  verilator
  dtc
  bc
  gcc
  g++
  c++
  ar
  ld
```

If the runner fails during toolchain setup:

```text
Check one of these prefixes exists:
  riscv64-unknown-elf-
  riscv64-elf-
  riscv64-none-elf-

Override if needed:
  RISCV_TOOL_PREFIX=<prefix> ./scripts/run-local-occamy-minimal.sh
```

If simulator build fails:

```text
Check VERILATOR_ROOT.
Check platforms/occamy/target/sim/Makefile.
Check cfg/single-cluster.hjson is active through CFG_OVERRIDE.
Check Verilator version compatibility.
```

If simulation runs but verification fails:

```text
Check device trace:
  rg '0x80000524.*00732023' platforms/occamy/target/sim/logs/trace_hart_00001.dasm

Check host interrupt clear path:
  rg '0x80000464.*04000737' platforms/occamy/target/sim/trace_hart_00.dasm

Check host tohost exit:
  rg '0x80000068.*00a2a023' platforms/occamy/target/sim/trace_hart_00.dasm
```

If those markers are missing, the run is not a valid M0 proof.
