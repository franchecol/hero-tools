# Local Occamy M0 Manual Replay

This document is an educational, line-by-line reconstruction of the M0 flow.
It intentionally does not paste or recreate the real source files used by M0.
Instead, it shows the order of operations, the build handoff points, and the
commands that the automated scripts normally hide.

Use this document when you want to type the M0 phases manually. For the complete
milestone progression and other document choices, start with the
[Local Occamy Milestone Roadmap](local-occamy-roadmap.md).

The canonical reproducible entry point is:

```bash
./scripts/bootstrap-local-occamy-minimal.sh
```

For normal reproduction, use that script. It resolves the repository root from
its own location, so it does not depend on `/home/ftv` or any other username.
This document is for understanding and manually replaying what the script does.

The reproducibility inputs are tracked here:

```text
scripts/occamy-m0.lock.env
  Pins the Occamy commit and the known-good tool versions.

scripts/requirements-occamy-m0.txt
  Pins the Python dependency versions.

scripts/patches/occamy-m0-verilator.patch
  Carries the Verilator compatibility changes required by the pinned Occamy
  revision.
```

Related references:

- [M0 Bootstrap And Runner](local-occamy-m0-bootstrap-runner.md) explains the automation.
- [M0 Deep Dive](local-occamy-m0-deep-dive.md) explains architecture, traces, and waveforms.
- [Device-Side Snitch Comparison](local-occamy-device-side-snitch-comparison.md) compares standalone Snitch with Occamy.

## 1. What Manual Replay Means

Manual replay means:

```text
Do the same phases as M0, but type each phase explicitly.
```

It does not mean:

```text
Copy the real Snitch payload source into this document.
Copy the real CVA6 host source into this document.
Replace the actual Makefiles with shell commands forever.
```

The real flow still depends on the actual files in the Occamy checkout.  This
manual only explains the flow around them.

The M0 shape is:

```text
host tools
  -> Occamy checkout
  -> Python generation environment
  -> reduced single-cluster Occamy headers
  -> Verilator simulator
  -> Snitch device payload
  -> CVA6 host ELF embedding the Snitch payload
  -> simulation
  -> trace verification
```

## 2. Start From The Repository Root

Use the `hero-tools` root as the working directory. Replace the example path
with the location of your checkout:

```bash
cd /home/ftv/builds/hero-tools
```

Check that this is really the repository root:

```bash
test -d .git
test -f Makefile
test -f hero.mk
test -f scripts/run-local-occamy-minimal.sh
```

The top-level `Makefile` is very small.  Conceptually it does this:

```make
HERO_ROOT ?= $(shell pwd)
include $(HERO_ROOT)/hero.mk
```

For M0, the top-level Makefile is not the main actor.  The important Makefiles
are inside:

```text
platforms/occamy/target/sim
platforms/occamy/target/sim/sw/device/apps/minimal_irq
platforms/occamy/target/sim/sw/host/apps/offload
```

## 3. Check The Required Host Tools

The runner checks these commands before doing real work:

```bash
command -v python
command -v make
command -v rg
command -v bender
command -v verilator
command -v dtc
command -v bc
command -v gcc
command -v g++
command -v c++
command -v ar
command -v ld
```

These tools cover three different jobs:

```text
Python tools
  Generate Occamy headers and configuration-derived files.

Build tools
  Compile host-side C/C++ simulator support code.

Hardware/simulation tools
  Resolve Bender dependencies and build the Verilated Occamy model.
```

## 4. Ensure The Occamy Checkout Exists

The automated bootstrap expects Occamy here:

```text
platforms/occamy
```

If it is missing, the script clones the expected fork branch and then checks
out the exact commit recorded in `scripts/occamy-m0.lock.env`. Manually, the
equivalent sequence is:

```bash
mkdir -p platforms
git clone --branch occamy-minimal-bootstrap --single-branch \
  https://github.com/franchecol/occamy.git \
  platforms/occamy
git -C platforms/occamy checkout --detach \
  2ffef40126b5deb2bc14ec4c9a2ed0fa94b9a6c3
```

If it already exists, inspect it instead of overwriting it:

```bash
cd platforms/occamy
git remote -v
git branch --show-current
cd /home/ftv/builds/hero-tools
```

Expected source revision:

```text
branch source: occamy-minimal-bootstrap
commit: 2ffef40126b5deb2bc14ec4c9a2ed0fa94b9a6c3
```

Expected remote target:

```text
github.com/franchecol/occamy
```

The exact remote URL may be HTTPS or SSH.  The important part is that it points
to the matching Occamy fork, not to an unrelated upstream checkout.

## 5. Check That The M0 Files Exist

For M0, the minimum Occamy-side files are:

```bash
test -f platforms/occamy/target/sim/sw/device/apps/minimal_irq/Makefile
test -f platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
test -f platforms/occamy/target/sim/sw/host/apps/offload/Makefile
test -f platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
test -f platforms/occamy/target/sim/Makefile
test -f platforms/occamy/target/sim/cfg/single-cluster.hjson
```

This manual does not reproduce the contents of `minimal_irq.S` or `offload.c`.
For educational purposes, treat them as black boxes with these roles:

```text
minimal_irq.S
  Snitch-side payload.  One Snitch hart writes to the host software-interrupt
  MMIO address, then parks.

offload.c
  CVA6-side host program.  It configures the Snitch boot address, wakes the
  cluster, waits for the interrupt, and exits the simulation.
```

## 6. Check The Verilator Compatibility Patch

The pinned Occamy commit needs the tracked M0 compatibility patch:

```bash
git -C platforms/occamy apply --check \
  "$(pwd)/scripts/patches/occamy-m0-verilator.patch"
git -C platforms/occamy apply \
  "$(pwd)/scripts/patches/occamy-m0-verilator.patch"
```

The bootstrap performs this operation idempotently: it applies the patch when
needed and accepts it when it is already applied. The patched simulator
Makefile includes support objects and controls needed by newer Verilator
builds:

```bash
rg 'verilated_timing\.o' platforms/occamy/target/sim/Makefile
rg 'verilated_threads\.o' platforms/occamy/target/sim/Makefile
```

If either search fails, the checkout is probably not the expected branch.

## 7. Create The Python Environment

The runner uses a repository-local virtual environment:

```bash
python -m venv .venv-occamy
. .venv-occamy/bin/activate
```

Install the exact Python packages used by the verified M0 environment:

```bash
python -m pip install --no-deps \
  --requirement scripts/requirements-occamy-m0.txt
```

The runner synchronizes this requirements file on every invocation. Already
installed matching packages are reused.

The known-good Python version is also recorded in
`scripts/occamy-m0.lock.env`. By default, a version mismatch stops the
reproducible run rather than silently testing a different environment.

## 8. Resolve `VERILATOR_ROOT`

Occamy's simulator build needs Verilator support sources, for example:

```text
verilated.cpp
verilated_dpi.cpp
verilated_vcd_c.cpp
verilated_timing.cpp
verilated_threads.cpp
```

Find the Verilator root:

```bash
verilator -V | rg 'VERILATOR_ROOT'
```

Then export it.  On many Linux installs this is:

```bash
export VERILATOR_ROOT=/usr/share/verilator
export VLT_ROOT="${VERILATOR_ROOT}"
```

Validate the path:

```bash
test -f "${VERILATOR_ROOT}/include/verilated.cpp"
```

If that file is not present, `VERILATOR_ROOT` is wrong.

## 9. Resolve The Bare-Metal RISC-V Toolchain

Occamy's M0 Makefiles expect the canonical prefix:

```text
riscv64-unknown-elf-
```

Check for the canonical tools:

```bash
command -v riscv64-unknown-elf-gcc
command -v riscv64-unknown-elf-objcopy
command -v riscv64-unknown-elf-objdump
command -v riscv64-unknown-elf-readelf
```

Some systems provide `riscv64-elf-*` instead.  If that is your case, create
compatibility symlinks under `~/bin`:

```bash
mkdir -p "${HOME}/bin"
export PATH="${HOME}/bin:${PATH}"
ln -sf "$(command -v riscv64-elf-gcc)"     "${HOME}/bin/riscv64-unknown-elf-gcc"
ln -sf "$(command -v riscv64-elf-objcopy)" "${HOME}/bin/riscv64-unknown-elf-objcopy"
ln -sf "$(command -v riscv64-elf-objdump)" "${HOME}/bin/riscv64-unknown-elf-objdump"
ln -sf "$(command -v riscv64-elf-readelf)" "${HOME}/bin/riscv64-unknown-elf-readelf"
```

The automated runner creates a larger set of aliases.  The four above are the
critical ones checked directly by the M0 runner.

## 10. Select The M0 Mode

The script mode for M0 is:

```bash
APP_MODE=minimal_irq
```

The selected paths are:

```bash
SIM_DIR=platforms/occamy/target/sim
DEVICE_APP_DIR="${SIM_DIR}/sw/device/apps/minimal_irq"
HOST_APP_DIR="${SIM_DIR}/sw/host/apps/offload"
HOST_ELF="${HOST_APP_DIR}/build/offload-minimal_irq.elf"
DEVICE_BIN="${DEVICE_APP_DIR}/build/minimal_irq.bin"
DEVICE_SYMBOL_ELF="${DEVICE_APP_DIR}/build/minimal_irq.elf"
```

These names explain the M0 split:

```text
DEVICE_APP_DIR
  The Snitch-side program.

HOST_APP_DIR
  The CVA6-side program.

DEVICE_BIN
  Raw Snitch payload bytes.

HOST_ELF
  Final CVA6 ELF that embeds the raw Snitch payload.
```

## 11. Build Reduced Occamy Headers

The reduced M0 simulation uses the single-cluster configuration:

```text
platforms/occamy/target/sim/cfg/single-cluster.hjson
```

Build the generated headers:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  all-headers
```

Conceptually this phase turns configuration into generated files such as:

```text
base-address headers
memory-map headers
configuration packages
generated hardware include files
```

The important point is that the software and hardware now agree on the reduced
single-cluster address map.

## 12. Build The Verilator Simulator

Build the reduced Occamy simulator:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  VLT='verilator --timing -DASSERTS_OFF' \
  VERILATOR_ROOT="${VERILATOR_ROOT}" \
  VLT_ROOT="${VLT_ROOT}" \
  VLT_JOBS=1 \
  VLT_TRACE=0 \
  VLT_PROF=0 \
  VLT_OUTPUT_SPLIT=5000 \
  VLT_OUTPUT_SPLIT_CFUNCS=5000 \
  CC=cc \
  CXX=c++ \
  CXXFLAGS='-include cstdint -fcoroutines' \
  bin/occamy_top.vlt
```

Expected simulator artifact:

```text
platforms/occamy/target/sim/bin/occamy_top.vlt
```

This binary is the executable Verilated model of the reduced Occamy system.

`VLT_JOBS=1` keeps the generated C++ build serial. This is the conservative
reproducible default and avoids a precompiled
header race seen with Verilator 5.048.  `VLT_TRACE=0` and `VLT_PROF=0` keep the
default M0 simulator lean by disabling VCD generation and Verilator C-function
profiling.  The M0 proof only needs the DASM traces, not `sim.vcd`.
`VLT_OUTPUT_SPLIT=5000` and `VLT_OUTPUT_SPLIT_CFUNCS=5000` split the generated
C++ into smaller files so one huge compiler process does not dominate memory.

The simulator Makefile records the complete Verilator build configuration
under `work-vlt`; if the version or relevant flags change, it automatically
discards incompatible generated objects before rebuilding.

`VLT_JOBS=4` was also tested successfully on the reference machine and reduced
the Verilator wall time from about 638 seconds to about 440 seconds. It uses
considerably more RAM and swap, so it is an opt-in performance setting:

```bash
VLT_JOBS=4 ./scripts/bootstrap-local-occamy-minimal.sh
```

## 13. Build The Snitch Device Payload

Clean the M0 device app:

```bash
make -C platforms/occamy/target/sim/sw/device/apps/minimal_irq clean
```

Build the M0 device app:

```bash
make -C platforms/occamy/target/sim/sw/device/apps/minimal_irq all
```

Expected artifacts:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.elf
platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin
```

The ELF is useful for symbols and disassembly.  The raw binary is what the host
build embeds.

At the flow level, the device payload does this:

```text
read Snitch hart ID
if hart ID is not the selected worker, park
write 1 to host software interrupt MMIO
fence
park forever
```

## 14. Build The CVA6 Host Application

Clean the host app:

```bash
make -C platforms/occamy/target/sim/sw/host/apps/offload clean
```

Build the host app with the M0 device app selected:

```bash
make -C platforms/occamy/target/sim/sw/host/apps/offload \
  DEVICE_APPS=minimal_irq
```

Finalize the host app:

```bash
make -C platforms/occamy/target/sim/sw/host/apps/offload \
  finalize-build \
  DEVICE_APPS=minimal_irq
```

Expected artifact:

```text
platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf
```

The reason there are two host build phases is that the host ELF needs to know
where the embedded Snitch payload lands.  The final link produces a CVA6 ELF
that contains the Snitch binary and exposes the `snitch_main` address used by
the host startup path.

At the flow level, the host program does this:

```text
release and ungate the Snitch quadrant
de-isolate the quadrant
enable host software interrupts
write Snitch entry address to SoC scratch register
write communication-buffer pointer to SoC scratch register
wake the Snitch cluster through cluster-local interrupt registers
wait in WFI until Snitch raises the host software interrupt
clear the host software interrupt
return so startup code writes to tohost
```

## 15. Run The Simulation

Remove stale traces before running:

```bash
rm -f platforms/occamy/target/sim/uart0.log
rm -f platforms/occamy/target/sim/trace_hart_00.dasm
rm -f platforms/occamy/target/sim/logs/trace_hart_0000*.dasm
```

Run the Verilated Occamy model with the CVA6 host ELF:

```bash
cd platforms/occamy/target/sim
./bin/occamy_top.vlt sw/host/apps/offload/build/offload-minimal_irq.elf
cd /home/ftv/builds/hero-tools
```

The simulator loads the host ELF as the main program.  The Snitch payload is
not passed as a separate command-line argument because it has already been
embedded into the host ELF.

## 16. Verify The M0 Traces

Check that the host trace exists:

```bash
test -f platforms/occamy/target/sim/trace_hart_00.dasm
```

Check that the Snitch hart trace exists:

```bash
test -f platforms/occamy/target/sim/logs/trace_hart_00001.dasm
```

First derive the relevant instruction addresses from the built ELFs:

```bash
HOST_ELF=platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf
DEVICE_ELF=platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.elf

SNITCH_BASE=$(riscv64-unknown-elf-nm -n "${HOST_ELF}" | awk '
  $NF == "snitch_main" && !found {
    value = "0x" $1
    found = 1
  }
  END { print value }
')

DEVICE_STORE_OFFSET=$(riscv64-unknown-elf-objdump -d "${DEVICE_ELF}" | awk '
  /sw[[:space:]]+t2,0\(t1\).*4000000/ && !found {
    sub(/:$/, "", $1)
    value = "0x" $1
    found = 1
  }
  END { print value }
')

DEVICE_STORE_PC=$(printf '0x%x\n' \
  $((SNITCH_BASE + DEVICE_STORE_OFFSET)))

HOST_CLEAR_PC=$(riscv64-unknown-elf-objdump -d "${HOST_ELF}" | awk '
  /sw[[:space:]]+zero,0\(a4\).*4000000/ && !found {
    sub(/:$/, "", $1)
    value = "0x" $1
    found = 1
  }
  END { print value }
')

HOST_EXIT_PC=$(riscv64-unknown-elf-objdump -d "${HOST_ELF}" | awk '
  /sw[[:space:]]+a0,0\(t0\)/ && !found {
    sub(/:$/, "", $1)
    value = "0x" $1
    found = 1
  }
  END { print value }
')
```

Then verify the semantic events at those derived addresses:

```bash
rg "${DEVICE_STORE_PC}.*DASM\\(00732023\\).*opa': 0x4000000.*gpr_rdata_1': 0x1" \
  platforms/occamy/target/sim/logs/trace_hart_00001.dasm

rg "${HOST_CLEAR_PC}.*DASM\\(00072023\\)" \
  platforms/occamy/target/sim/trace_hart_00.dasm

rg "${HOST_EXIT_PC}.*DASM\\(00a2a023\\)" \
  platforms/occamy/target/sim/trace_hart_00.dasm
```

These checks prove:

```text
Snitch wrote value 1 to the host software-interrupt MMIO address.
The host executed the store that clears that interrupt.
The host executed the final tohost store that terminates the simulation.
```

The script computes these addresses for every build. A compiler or linker
layout change therefore does not invalidate verification merely because a
function moved.

## 17. The Complete Manual Sequence

For reference, the manual M0 command sequence is:

```bash
HERO_TOOLS_ROOT=/path/to/hero-tools
cd "${HERO_TOOLS_ROOT}"

test -d .git
test -f scripts/run-local-occamy-minimal.sh
test -f scripts/occamy-m0.lock.env
test -f scripts/requirements-occamy-m0.txt
test -f scripts/patches/occamy-m0-verilator.patch
test -d platforms/occamy
test -f platforms/occamy/target/sim/sw/device/apps/minimal_irq/Makefile
test -f platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
test -f platforms/occamy/target/sim/sw/host/apps/offload/Makefile
test -f platforms/occamy/target/sim/Makefile
test -f platforms/occamy/target/sim/cfg/single-cluster.hjson

command -v python
command -v make
command -v rg
command -v bender
command -v verilator
command -v dtc
command -v bc
command -v gcc
command -v g++
command -v c++
command -v ar
command -v ld

# Load and validate the pinned source revision.
. scripts/occamy-m0.lock.env
test "$(git -C platforms/occamy rev-parse HEAD)" = "${OCCAMY_M0_COMMIT}"

# Apply only when the reverse check says it is not already applied.
if ! git -C platforms/occamy apply --reverse --check \
  "${HERO_TOOLS_ROOT}/scripts/patches/occamy-m0-verilator.patch" \
  >/dev/null 2>&1; then
  git -C platforms/occamy apply --check \
    "${HERO_TOOLS_ROOT}/scripts/patches/occamy-m0-verilator.patch"
  git -C platforms/occamy apply \
    "${HERO_TOOLS_ROOT}/scripts/patches/occamy-m0-verilator.patch"
fi

python -m venv .venv-occamy
. .venv-occamy/bin/activate
python -m pip install --no-deps \
  --requirement scripts/requirements-occamy-m0.txt

export VERILATOR_ROOT=/usr/share/verilator
export VLT_ROOT="${VERILATOR_ROOT}"
test -f "${VERILATOR_ROOT}/include/verilated.cpp"

export PATH="${HOME}/bin:${PATH}"
command -v riscv64-unknown-elf-gcc
command -v riscv64-unknown-elf-objcopy
command -v riscv64-unknown-elf-objdump
command -v riscv64-unknown-elf-readelf

rg 'verilated_timing\.o' platforms/occamy/target/sim/Makefile
rg 'verilated_threads\.o' platforms/occamy/target/sim/Makefile

make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  all-headers

make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  VLT='verilator --timing -DASSERTS_OFF' \
  VERILATOR_ROOT="${VERILATOR_ROOT}" \
  VLT_ROOT="${VLT_ROOT}" \
  VLT_JOBS=1 \
  VLT_TRACE=0 \
  VLT_PROF=0 \
  VLT_OUTPUT_SPLIT=5000 \
  VLT_OUTPUT_SPLIT_CFUNCS=5000 \
  CC=cc \
  CXX=c++ \
  CXXFLAGS='-include cstdint -fcoroutines' \
  bin/occamy_top.vlt

make -C platforms/occamy/target/sim/sw/device/apps/minimal_irq clean
make -C platforms/occamy/target/sim/sw/device/apps/minimal_irq all

make -C platforms/occamy/target/sim/sw/host/apps/offload clean
make -C platforms/occamy/target/sim/sw/host/apps/offload DEVICE_APPS=minimal_irq
make -C platforms/occamy/target/sim/sw/host/apps/offload finalize-build DEVICE_APPS=minimal_irq

rm -f platforms/occamy/target/sim/uart0.log
rm -f platforms/occamy/target/sim/trace_hart_00.dasm
rm -f platforms/occamy/target/sim/logs/trace_hart_0000*.dasm

cd platforms/occamy/target/sim
./bin/occamy_top.vlt sw/host/apps/offload/build/offload-minimal_irq.elf
cd "${HERO_TOOLS_ROOT}"

test -f platforms/occamy/target/sim/trace_hart_00.dasm
test -f platforms/occamy/target/sim/logs/trace_hart_00001.dasm

# Derive and check the trace PCs using the commands from step 16.
```

This is essentially what `scripts/run-local-occamy-minimal.sh minimal_irq`
automates. The runner additionally validates the exact tool versions from the
lock file before building.

For deliberate experiments with a newer tool or a different Occamy revision,
the safety checks can be relaxed explicitly:

```bash
M0_STRICT_VERSIONS=0 M0_ALLOW_UNPINNED=1 \
  ./scripts/bootstrap-local-occamy-minimal.sh
```

That is an unverified compatibility test, not the pinned reproducible M0 path.

## 18. Why A Makefile Still Appears In A Manual Replay

Even in a manual explanation, Makefiles remain part of the flow because they
encode real build knowledge:

```text
which compiler prefix to use
which linker script to use
how to convert ELF to BIN
how to embed the Snitch payload into the CVA6 host ELF
which generated Occamy headers are needed
which Verilator flags and support objects are required
```

Replacing every Makefile line with raw compiler and linker commands would make
the manual longer, more fragile, and less educational.  The useful manual view
is:

```text
call this Makefile target
understand what artifact it creates
understand why the next phase needs that artifact
```

That is why this document uses `make -C ...` explicitly instead of hiding it
behind the bootstrap script, but still lets each Makefile perform its real job.
