# Device-Side Snitch: Pure Snitch vs Occamy

This document compares two ways of testing the Snitch side of this project:

```text
Pure Snitch path
  Use the upstream snitch_cluster repository by itself.
  Build a Snitch-only simulator.
  Compile a Snitch ELF.
  Run that ELF directly on snitch_cluster.vlt.

Occamy path
  Use Occamy as the surrounding heterogeneous SoC.
  Build an Occamy simulator containing CVA6 plus one Snitch cluster.
  Compile a CVA6 host ELF and a Snitch device payload.
  Embed the Snitch payload into the host ELF.
  Let CVA6 wake Snitch, pass data, and observe completion.
```

The scope here is deliberately device-side focused.  Host code is only
discussed when it explains how the Snitch payload is loaded, started, or
observed.

Use this document for the standalone-Snitch versus Occamy comparison. For the
incremental M0-through-M4 project progression, start with the
[Local Occamy Milestone Roadmap](local-occamy-roadmap.md).

## 1. Main Conclusion

Pure Snitch and Occamy are not two equivalent ways to do the same test.

They answer different questions:

```text
Pure Snitch answers:
  Can a Snitch cluster run this kernel as a standalone manycore target?
  Does the Snitch runtime, TCDM allocation, DMA, barriers, and tracing work?
  Is the device-side algorithm correct before host integration exists?

Occamy answers:
  Can a CVA6 host start a Snitch payload inside a heterogeneous SoC?
  Can the payload signal completion back to the host?
  Can the host pass data or a payload image into the Snitch side?
  Can the same Snitch-side software style be used inside the bigger SoC?
```

For learning Snitch itself, use pure `snitch_cluster`.

For this fork's thesis path, use Occamy, because the real project is not "run a
Snitch kernel in isolation."  The real project is "make a host-controlled
heterogeneous RISC-V system usable through HeroSDK/OpenMP."

## 2. Device-Side Boundary

The "device side" means the code executed by the Snitch cluster.

In pure Snitch:

```text
┌─────────────────────────────────────────────────────────────┐
│ snitch_cluster.vlt                                          │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Snitch cluster                                        │  │
│  │                                                       │  │
│  │  axpy.elf is the whole program                        │  │
│  │  main() starts directly on Snitch                     │  │
│  │  snRuntime coordinates cores, DMA, TCDM, barriers     │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

In Occamy:

```text
┌─────────────────────────────────────────────────────────────┐
│ occamy_top.vlt                                              │
│                                                             │
│  ┌────────────────────┐        ┌─────────────────────────┐  │
│  │ CVA6 host          │        │ Snitch cluster device   │  │
│  │                    │        │                         │  │
│  │ reset/deisolate    │        │ payload starts after    │  │
│  │ write scratch regs │───────▶│ CVA6 programs entry     │  │
│  │ wake cluster       │        │ and sends wakeup        │  │
│  │ wait interrupt     │◀───────│ writes host interrupt   │  │
│  └────────────────────┘        └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

That difference is the whole reason Occamy is more complicated.

Pure Snitch treats Snitch as the computer.

Occamy treats Snitch as an accelerator inside a bigger computer.

## 3. Official Pure Snitch Tutorial Flow

The official Snitch tutorial is written for the upstream
`pulp-platform/snitch_cluster` repository.  It assumes commands are run from
the root of that repository unless stated otherwise.

Source:

```text
https://pulp-platform.github.io/snitch_cluster/ug/getting_started.html
https://pulp-platform.github.io/snitch_cluster/ug/tutorial.html
```

### 3.1 Clone Snitch

Official standalone checkout:

```bash
git clone https://github.com/pulp-platform/snitch_cluster.git --recurse-submodules
cd snitch_cluster
```

If the repository was cloned without submodules:

```bash
git submodule update --init --recursive
```

The official guide strongly recommends the provided Docker containers when not
using ETH/IIS infrastructure, because the full tool environment is non-trivial.

Hardware container:

```bash
docker pull ghcr.io/pulp-platform/snitch_cluster-hw:main
docker run -it -v "$PWD:/repo" ghcr.io/pulp-platform/snitch_cluster-hw:main
```

Software container:

```bash
docker pull ghcr.io/pulp-platform/snitch_cluster-sw:main
docker run -it -v "$PWD:/repo" ghcr.io/pulp-platform/snitch_cluster-sw:main
```

Important practical note:

```text
Pure Snitch has its own expected tool environment.
Our Occamy branch has its own bootstrap scripts.
Do not assume that a toolchain sufficient for M0 automatically satisfies
every pure-snitch_cluster tutorial target.
```

### 3.2 Build The Snitch Hardware Simulator

Official tutorial command:

```bash
make verilator
```

What this does:

```text
RTL sources
  ↓
Verilator
  ↓
C++ model and C++ testbench
  ↓
Snitch-only simulator executable
  ↓
target/sim/build/... and a runnable snitch_cluster.vlt-style binary
```

The official tutorial also lists QuestaSim and VCS, but Verilator is the
open-source path:

```bash
make DEBUG=ON vsim
make vcs
```

For this local project, the important point is not the exact simulator backend.
The important point is that the pure Snitch simulator contains only the Snitch
cluster environment, not a CVA6 host and not the Occamy SoC.

### 3.3 Configure The Snitch Hardware

The tutorial explains that Snitch cluster RTL is generated from configuration
files.  A configuration controls things like the cluster shape and generated
headers/linker artifacts.

Typical override style:

```bash
make CFG_OVERRIDE=cfg/omega.json verilator
```

Meaning:

```text
cfg/default.json or cfg/default.hjson
  default cluster configuration

CFG_OVERRIDE=...
  choose a different cluster configuration

cfg/lru.json or cfg/lru.hjson
  least-recently-used config remembered by the build system
```

This matters because software and hardware must match.  If the hardware says
"this cluster has this many cores, this TCDM layout, and these memory ranges,"
the Snitch runtime and linker scripts need the same view.

### 3.4 Build Snitch Software

Official tutorial command for all software:

```bash
make DEBUG=ON sw -j
```

Official tutorial command for a specific application:

```bash
make DEBUG=ON axpy -j
```

The tutorial's AXPY example produces artifacts such as:

```text
sw/kernels/blas/axpy/build/axpy.elf
sw/kernels/blas/axpy/build/axpy.dump
```

The important outputs are:

```text
axpy.elf
  The executable loaded into the Snitch simulator.

axpy.dump
  The disassembly used to understand which instructions were generated.

trace logs
  Generated after simulation, one per hart.
```

### 3.5 Run A Snitch Simulation

Official tutorial command:

```bash
snitch_cluster.vlt sw/kernels/blas/axpy/build/axpy.elf
```

Equivalent idea with explicit path:

```bash
target/sim/bin/snitch_cluster.vlt sw/kernels/blas/axpy/build/axpy.elf
```

What this proves:

```text
The Snitch simulator can load a Snitch ELF.
The Snitch cores can execute the application.
The runtime can start the cores.
The application can use Snitch runtime APIs.
The simulator can produce per-hart traces.
```

What this does not prove:

```text
No CVA6 host was involved.
No Occamy SoC registers were involved.
No host wakeup sequence was involved.
No host/device offload ABI was involved.
No HeroSDK OpenMP target path was involved.
```

### 3.6 Inspect Traces And Visualize Execution

After simulation, the official tutorial describes trace conversion:

```bash
make traces -j
make annotate -j
```

For region-level visualization:

```bash
make visual-trace ROI_SPEC=sw/kernels/blas/axpy/roi.json -j
```

The generated Perfetto trace can be opened in:

```text
https://ui.perfetto.dev/
```

This is one of the strongest reasons to use pure Snitch when learning the
device side.  The tutorial is designed around per-core Snitch traces and
kernel-level timing regions.

### 3.7 Develop A First Snitch Application

The official tutorial's first-application flow is:

```text
1. Create a new application directory.
2. Write a C file that includes snrt.h.
3. Write or generate a data.h input file.
4. Add an app.mk file.
5. Register the app in the Snitch software build list.
6. Rebuild software.
7. Run the resulting ELF on snitch_cluster.vlt.
8. Verify results either inside the simulated program or with a Python script.
```

The tutorial example uses Snitch runtime calls such as:

```c
#include "snrt.h"

int core_idx = snrt_cluster_core_idx();

if (snrt_is_compute_core()) {
    /* compute work */
}
```

This is the pure Snitch programming model: the Snitch application is the main
program, and it directly coordinates Snitch cores.

## 4. The Pinned Snitch Checkout Inside Occamy

This `hero-tools` branch does not vendor Snitch directly at the repo root.
Occamy brings Snitch through Bender.

Current local path:

```text
platforms/occamy/deps/snitch_cluster
  → symlink to ../.bender/git/checkouts/snitch_cluster-85bc3373558d290b
```

Useful pinned checkout paths:

```text
platforms/occamy/deps/snitch_cluster/target/snitch_cluster/Makefile
platforms/occamy/deps/snitch_cluster/target/snitch_cluster/sw/Makefile
platforms/occamy/deps/snitch_cluster/target/snitch_cluster/sw/apps/blas/axpy/Makefile
platforms/occamy/deps/snitch_cluster/sw/blas/axpy/src/main.c
platforms/occamy/deps/snitch_cluster/sw/blas/axpy/verify.py
```

One important mismatch:

```text
Official tutorial path:
  sw/kernels/blas/axpy/...

Pinned checkout path used here:
  sw/blas/axpy/...
  target/snitch_cluster/sw/apps/blas/axpy/...
```

That means the concepts from the tutorial transfer directly, but some paths in
the tutorial do not match this pinned checkout.

For a pure Snitch experiment using the pinned checkout, the starting point is:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/deps/snitch_cluster/target/snitch_cluster
```

The local target Makefile exposes the direct Verilator binary target:

```bash
make bin/snitch_cluster.vlt
```

The local software tree is entered through:

```bash
make sw
```

Or for the local AXPY wrapper:

```bash
make -C sw/apps/blas/axpy
```

Expected local AXPY ELF location:

```text
target/snitch_cluster/sw/apps/blas/axpy/build/axpy.elf
```

The corresponding simulation idea is:

```bash
bin/snitch_cluster.vlt sw/apps/blas/axpy/build/axpy.elf
```

This pure-pinned-Snitch path is useful, but it is not the path currently used
by the local M0/M1/M2 scripts.  The local scripts build Occamy, not a
standalone Snitch-only simulator.

## 5. What The Pure Snitch AXPY Device Code Does

Pinned source:

```text
platforms/occamy/deps/snitch_cluster/sw/blas/axpy/src/main.c
```

The structure is:

```text
main()
  calculate each cluster's slice of the vectors
  allocate local TCDM space using snrt_l1_next()
  DM core copies x and y into TCDM with snrt_dma_start_1d()
  all cores synchronize with snrt_cluster_hw_barrier()
  compute cores run axpy()
  all cores synchronize again
  DM core copies z back out of TCDM
  final synchronization
  return 0
```

Conceptually:

```text
remote memory
  x[], y[], z[]
      │
      │ DMA by DM core
      ▼
TCDM / L1 scratchpad
  local_x, local_y, local_z
      │
      │ compute cores
      ▼
TCDM result
      │
      │ DMA by DM core
      ▼
remote z[]
```

Key Snitch runtime calls:

```text
snrt_cluster_num()
  How many clusters exist.

snrt_cluster_idx()
  Which cluster this code is running on.

snrt_l1_next()
  Get scratchpad/TCDM memory for local buffers.

snrt_is_dm_core()
  Select the data-mover core.

snrt_dma_start_1d()
  Start a DMA copy.

snrt_dma_wait_all()
  Wait for outstanding DMA copies to finish.

snrt_cluster_hw_barrier()
  Synchronize cluster cores.

snrt_mcycle()
  Read cycle counter for benchmarking regions.
```

That is a real Snitch-style kernel: explicit local memory management, explicit
DMA, explicit barriers, and separate data-mover versus compute-core roles.

## 6. How Occamy Uses Snitch On The Device Side

Occamy does not simply run `axpy.elf` directly on `snitch_cluster.vlt`.

The local Occamy runner builds this:

```text
CVA6 host ELF
  contains .devicebin section
  includes raw Snitch payload bytes through .incbin DEVICEBIN
  exposes symbol snitch_main

Snitch device payload
  built separately
  converted to .bin
  embedded into the host ELF

Occamy simulator
  loads the host ELF
  CVA6 programs scratch registers
  CVA6 wakes Snitch cluster
  Snitch jumps to payload
```

The embedding point is:

```text
platforms/occamy/target/sim/sw/host/runtime/start.S
```

Relevant idea:

```asm
.section .devicebin,"a",@progbits
.globl snitch_main
.align 4
snitch_main:
#ifdef DEVICEBIN
    .incbin DEVICEBIN
#endif
```

The host programming point is:

```text
platforms/occamy/target/sim/sw/host/runtime/host.c
```

Relevant behavior:

```text
program_snitches()
  soc_ctrl_scratch_1 = address of snitch_main
  soc_ctrl_scratch_2 = address of comm_buffer

wakeup_snitches_cl()
  writes cluster-local interrupt set register

wait_snitches_done()
  waits for host software interrupt from device
```

The device-side helper that reads the host-passed communication buffer is:

```text
platforms/occamy/target/sim/sw/device/runtime/src/occamy_device.h
```

Relevant behavior:

```c
get_communication_buffer()
  returns (comm_buffer_t *)(*soc_ctrl_scratch_ptr(2))
```

So the Occamy device side is still Snitch code, but it is not booted like the
standalone tutorial.  It is started by CVA6 through Occamy platform registers.

## 7. Occamy M0 Device Payload

M0 device payload:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
```

M0 device build:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/Makefile
```

The payload is intentionally tiny:

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
    j       park
```

Meaning:

```text
hart 1:
  write 1 to 0x04000000
  this raises the CVA6 host software interrupt
  park forever

all other Snitch harts:
  park forever
```

Why M0 does not use `snrt.h`:

```text
M0 is not trying to validate a Snitch numerical kernel.
M0 is trying to validate the smallest CVA6 → Snitch → CVA6 control path.
Using assembly removes runtime variables from the first proof.
```

M0 proves:

```text
CVA6 can embed a Snitch payload.
CVA6 can program the Snitch entry point.
CVA6 can wake the cluster.
Snitch hart 1 can execute.
Snitch can write the global CLINT MSIP.
CVA6 can observe the completion interrupt.
The simulator exits cleanly.
```

M0 does not prove:

```text
Snitch runtime.
DMA.
TCDM allocation.
Shared-memory correctness.
OpenMP offload.
```

## 8. Occamy M1 Device Payload

M1 device payload:

```text
platforms/occamy/target/sim/sw/device/apps/roundtrip/src/roundtrip.S
```

M1 host side initializes:

```text
platforms/occamy/target/sim/sw/host/apps/roundtrip/src/roundtrip.c
```

The M1 device code does one extra thing beyond M0:

```text
1. Read the communication-buffer pointer from SoC scratch register 2.
2. Read comm_buffer.usr_data_ptr.
3. Treat that as a pointer to a 16-word host buffer.
4. Increment each word.
5. Signal host completion through 0x04000000.
```

The key device-side sequence is:

```asm
// soc_ctrl_scratch_2 holds the host communication buffer pointer.
lui     t1, 0x2000
lw      t2, 0x1c(t1)
lw      t3, 4(t2)
```

Then the loop:

```asm
loop_words:
    lw      t6, 0(t3)
    add     t6, t6, t5
    sw      t6, 0(t3)
    addi    t3, t3, 4
    addi    t4, t4, -1
    bnez    t4, loop_words
```

M1 proves:

```text
The host can pass a data pointer to the device.
The Snitch payload can dereference that pointer.
The Snitch payload can write back to host-visible memory.
The host can validate the result after completion.
```

M1 is still not a full Snitch runtime example.  It is a minimal data-path proof.

## 9. Occamy M2 Device Payload

M2 starts to look more like the pure Snitch tutorial because it reuses the
Snitch BLAS AXPY source.

Occamy AXPY wrapper:

```text
platforms/occamy/target/sim/sw/device/apps/blas/axpy/Makefile
```

It includes:

```make
include ../../../../../../../deps/snitch_cluster/sw/blas/axpy/Makefile
include ../../common.mk
```

Meaning:

```text
Snitch provides:
  the AXPY source structure
  data generation
  verify.py
  Snitch runtime style

Occamy adds:
  Occamy device runtime include paths
  generated Occamy platform headers
  Occamy memory linker scripts
  origin.ld relocation generated from the host ELF
  .bin output for host embedding
```

Occamy device common build file:

```text
platforms/occamy/target/sim/sw/device/apps/common.mk
```

Important differences from the pure Snitch app build:

```text
Pure Snitch app common.mk:
  builds an ELF intended to be loaded directly by snitch_cluster.vlt
  links against target/snitch_cluster runtime
  outputs ELF, DEP, DUMP, DWARF

Occamy device apps/common.mk:
  builds a payload intended to be embedded into a CVA6 host ELF
  links against Occamy's device runtime
  uses Occamy generated platform headers
  uses memory.ld and origin.ld
  outputs ELF, BIN, DUMP, DWARF
```

That `.bin` output is critical.  Occamy's host build embeds the binary payload.
The pure Snitch simulator does not need that packaging step.

## 10. Side-By-Side Comparison

```text
┌───────────────────────────┬─────────────────────────────┬────────────────────────────┐
│ Question                  │ Pure Snitch                 │ Occamy                     │
├───────────────────────────┼─────────────────────────────┼────────────────────────────┤
│ Simulator                 │ snitch_cluster.vlt          │ occamy_top.vlt             │
│ Main machine              │ Snitch cluster              │ CVA6-hosted Occamy SoC     │
│ Loaded program            │ Snitch ELF                  │ CVA6 host ELF              │
│ Device image              │ same as loaded ELF          │ embedded .devicebin payload│
│ Starts first              │ Snitch runtime/app          │ CVA6 host program          │
│ Snitch entry              │ normal ELF entry            │ host-programmed snitch_main│
│ Host required             │ no                          │ yes                        │
│ Completion                │ program exit / simulator rc │ Snitch interrupt to CVA6   │
│ Runtime focus             │ snRuntime                   │ Occamy runtime + snRuntime │
│ Memory model              │ Snitch target memory layout │ Occamy SoC memory map      │
│ Data movement             │ DMA/TCDM in Snitch program  │ host pointers + DMA/TCDM   │
│ Best first test           │ AXPY tutorial               │ minimal_irq                │
│ Best integration test     │ not applicable              │ roundtrip or axpy          │
│ Trace focus               │ Snitch per-hart traces      │ host trace + device traces │
└───────────────────────────┴─────────────────────────────┴────────────────────────────┘
```

The most important row is "Loaded program."

Pure Snitch:

```text
snitch_cluster.vlt axpy.elf
```

Occamy:

```text
occamy_top.vlt offload-axpy.elf
```

In Occamy, `offload-axpy.elf` is a host ELF.  The Snitch payload is inside it.

## 11. Step-By-Step: Pure Snitch AXPY Demonstration

This is the simplest "only Snitch" manual path, based on the official tutorial.

### 11.1 Use A Standalone Snitch Checkout

```bash
mkdir -p /home/ftv/builds/snitch-only
cd /home/ftv/builds/snitch-only
git clone https://github.com/pulp-platform/snitch_cluster.git --recurse-submodules
cd snitch_cluster
```

### 11.2 Use The Recommended Tool Environment

If using Docker:

```bash
docker pull ghcr.io/pulp-platform/snitch_cluster-hw:main
docker pull ghcr.io/pulp-platform/snitch_cluster-sw:main
```

Run a container with the repository mounted:

```bash
docker run -it -v "$PWD:/repo" ghcr.io/pulp-platform/snitch_cluster-hw:main
```

Inside the container:

```bash
cd /repo
```

If using a native environment, the official guide recommends modeling it after
the upstream Dockerfile.  Do not expect this local HeroSDK fork to solve all
pure-Snitch tutorial dependencies.

### 11.3 Build The Snitch Simulator

```bash
make verilator
```

Expected conceptual result:

```text
snitch_cluster.vlt or an equivalent generated Verilator simulator
```

### 11.4 Build AXPY

```bash
make DEBUG=ON axpy -j
```

Or build all software:

```bash
make DEBUG=ON sw -j
```

Expected conceptual result:

```text
sw/kernels/blas/axpy/build/axpy.elf
sw/kernels/blas/axpy/build/axpy.dump
```

If using the pinned checkout under this Occamy branch, adjust paths:

```bash
cd /home/ftv/builds/hero-tools/platforms/occamy/deps/snitch_cluster/target/snitch_cluster
make bin/snitch_cluster.vlt
make -C sw/apps/blas/axpy
```

Expected pinned-checkout result:

```text
sw/apps/blas/axpy/build/axpy.elf
sw/apps/blas/axpy/build/axpy.dump
sw/apps/blas/axpy/build/axpy.dwarf
```

### 11.5 Run The AXPY ELF

Official tutorial style:

```bash
snitch_cluster.vlt sw/kernels/blas/axpy/build/axpy.elf
```

Pinned-checkout style:

```bash
bin/snitch_cluster.vlt sw/apps/blas/axpy/build/axpy.elf
```

### 11.6 Read The Evidence

Look for:

```text
simulation exit code
logs/trace_hart_*.dasm
converted traces from make traces
annotated traces from make annotate
optional Perfetto trace from make visual-trace
```

The evidence is device-native:

```text
Which Snitch hart executed which instructions?
Where did the DM core issue DMA?
Where did compute cores enter the kernel?
Where are the barriers?
How many cycles did a region take?
```

That is different from Occamy M0, where the evidence is:

```text
Did CVA6 write the wakeup register?
Did Snitch write the host interrupt register?
Did CVA6 clear the interrupt and exit?
```

## 12. Step-By-Step: Occamy Device Demonstrations

The Occamy path starts from this repo:

```bash
cd /home/ftv/builds/hero-tools
```

### 12.1 M0 Minimal Interrupt

```bash
./scripts/run-local-occamy-minimal.sh minimal_irq
```

Device source:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
```

Device build output:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.elf
platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin
platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.dump
```

Host ELF:

```text
platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf
```

Simulator:

```text
platforms/occamy/target/sim/bin/occamy_top.vlt
```

Evidence:

```text
platforms/occamy/target/sim/trace_hart_00.dasm
  CVA6 host trace

platforms/occamy/target/sim/logs/trace_hart_00001.dasm
  Snitch hart 1 trace
```

### 12.2 M1 Roundtrip

```bash
./scripts/run-local-occamy-minimal.sh roundtrip
```

Device source:

```text
platforms/occamy/target/sim/sw/device/apps/roundtrip/src/roundtrip.S
```

Host source:

```text
platforms/occamy/target/sim/sw/host/apps/roundtrip/src/roundtrip.c
```

What to inspect:

```text
comm_buffer.usr_data_ptr on host
soc_ctrl_scratch_2 on device
stores into roundtrip_buffer
final host interrupt store
host-side validation exit
```

### 12.3 M2 AXPY

Prerequisite:

```bash
source scripts/setenv.sh
make hero-tc-llvm-axpy
```

Run:

```bash
./scripts/run-local-occamy-minimal.sh axpy
```

Device source reused from Snitch:

```text
platforms/occamy/deps/snitch_cluster/sw/blas/axpy/src/main.c
```

Occamy wrapper:

```text
platforms/occamy/target/sim/sw/device/apps/blas/axpy/Makefile
platforms/occamy/target/sim/sw/device/apps/common.mk
```

What makes M2 important:

```text
M0 and M1 prove tiny hand-written device payloads.
M2 proves the branch can carry a real Snitch-style runtime/kernel payload
through the Occamy host/device packaging flow.
```

## 13. How To Port A Pure Snitch Kernel Into Occamy

Use this mental workflow:

```text
1. Make the kernel work in pure Snitch first.
   This validates the device-side algorithm.

2. Identify the kernel's dependencies.
   snrt.h?
   snRuntime?
   math library?
   generated data.h?
   custom linker sections?

3. Add an Occamy device app wrapper.
   Place it under:
     platforms/occamy/target/sim/sw/device/apps/...

4. Include or reuse the Snitch source Makefile if possible.
   AXPY does this by including:
     deps/snitch_cluster/sw/blas/axpy/Makefile

5. Include Occamy's device apps/common.mk.
   This adds Occamy platform headers, runtime paths, linker scripts,
   and .bin generation.

6. Make the host build embed the new device .bin.
   For offload-style host packaging, DEVICE_APPS controls which
   payload is embedded.

7. Run the Occamy simulator.
   The command is no longer snitch_cluster.vlt kernel.elf.
   It is occamy_top.vlt host-with-device-payload.elf.

8. Verify both sides.
   Inspect host trace and Snitch trace.
```

The biggest porting change is not C syntax.  The biggest porting change is
execution ownership:

```text
Pure Snitch:
  kernel owns program start and exit.

Occamy:
  CVA6 owns start, payload placement, wakeup, and completion observation.
```

## 14. Why Occamy Is Preferred For This Project

Pure Snitch is cleaner for learning the accelerator.

Occamy is better for this project because it already provides:

```text
CVA6 host integration
SoC memory map
host/device control registers
cluster wakeup path
global CLINT interrupt path
Snitch cluster embedded in a bigger platform
generated platform headers
host-side payload embedding flow
the path HeroSDK expects for Occamy
```

If the thesis goal were only:

```text
Write and benchmark a Snitch kernel.
```

then pure `snitch_cluster` would be the natural base.

But the thesis goal is closer to:

```text
Make a host-controlled RISC-V accelerator usable through a portable
heterogeneous software stack.
```

For that, pure Snitch is a component test.  Occamy is the integration test.

## 15. Common Pitfalls

### Pitfall 1: "Snitch Tutorial Works" Does Not Mean "Occamy Works"

Pure Snitch can pass while Occamy fails, because Occamy adds:

```text
CVA6 host code
SoC reset/deisolation
scratch-register programming
cluster wakeup
payload embedding
different linker origin
different memory map
host completion interrupt
```

### Pitfall 2: "Occamy M0 Works" Does Not Mean "Snitch Runtime Works"

M0 is assembly.  It deliberately avoids `snrt.h`, DMA, TCDM allocation, and
runtime startup complexity.

M0 says:

```text
The host/device control path is alive.
```

It does not say:

```text
The full Snitch programming model is working.
```

M2 is the milestone that starts answering that second question.

### Pitfall 3: Official Snitch Paths May Not Match The Pinned Checkout

The official tutorial uses paths like:

```text
sw/kernels/blas/axpy
```

The pinned Snitch checkout used by this Occamy branch has:

```text
sw/blas/axpy
target/snitch_cluster/sw/apps/blas/axpy
```

Follow the tutorial concepts, but verify local paths with:

```bash
find platforms/occamy/deps/snitch_cluster -path '*axpy*' -maxdepth 8 -print
```

### Pitfall 4: A Snitch Cluster Is Not Just One Core

In the Occamy single-cluster setup, "single cluster" still means multiple
Snitch harts inside that cluster.

M0 chooses hart 1 for the only active operation:

```asm
csrr a0, mhartid
li   t0, 1
bne  a0, t0, park
```

That is why the important device trace is usually:

```text
platforms/occamy/target/sim/logs/trace_hart_00001.dasm
```

### Pitfall 5: ELF vs BIN Matters

Pure Snitch:

```text
simulator input = axpy.elf
```

Occamy device side:

```text
device build creates minimal_irq.elf
device build converts it to minimal_irq.bin
host build embeds minimal_irq.bin
simulator input = host ELF
```

If you try to run an Occamy device `.bin` directly like a pure Snitch ELF, that
is the wrong abstraction.

## 16. File Map

Pure Snitch, pinned through Occamy:

```text
platforms/occamy/deps/snitch_cluster
  Symlink to the Bender checkout of Snitch.

platforms/occamy/deps/snitch_cluster/target/snitch_cluster/Makefile
  Standalone Snitch target build logic.

platforms/occamy/deps/snitch_cluster/target/snitch_cluster/sw/Makefile
  Standalone Snitch software build entry.

platforms/occamy/deps/snitch_cluster/target/snitch_cluster/sw/apps/common.mk
  Standalone Snitch app build logic.

platforms/occamy/deps/snitch_cluster/sw/blas/axpy/src/main.c
  Snitch AXPY kernel using snRuntime, TCDM, DMA, and barriers.

platforms/occamy/deps/snitch_cluster/sw/blas/axpy/verify.py
  Python verifier used for AXPY-style simulation checking.
```

Occamy device side:

```text
platforms/occamy/target/sim/cfg/single-cluster.hjson
  Reduced local Occamy configuration: one S1 quadrant, one cluster.

platforms/occamy/target/sim/sw/device/apps/minimal_irq
  M0 device payload.

platforms/occamy/target/sim/sw/device/apps/roundtrip
  M1 device payload.

platforms/occamy/target/sim/sw/device/apps/blas/axpy
  M2 Occamy wrapper around Snitch AXPY.

platforms/occamy/target/sim/sw/device/apps/common.mk
  Occamy device app build logic.

platforms/occamy/target/sim/sw/device/runtime/src/occamy_device.h
  Device-side helpers for Occamy runtime behavior.

platforms/occamy/target/sim/sw/shared/runtime/heterogeneous_runtime.h
  Shared host/device communication structure and interrupt helper.
```

Occamy host files that matter to the device path:

```text
platforms/occamy/target/sim/sw/host/runtime/start.S
  Embeds DEVICEBIN at symbol snitch_main.

platforms/occamy/target/sim/sw/host/runtime/host.c
  Programs snitch_main and comm_buffer pointers, wakes cluster,
  waits for completion interrupt.

platforms/occamy/target/sim/sw/host/apps/offload/Makefile
  Builds host ELF variants that embed selected device payloads.
```

## 17. Practical Recommendation

Use this order when developing a new Snitch-side idea:

```text
Step 1: pure Snitch
  Make the kernel work on snitch_cluster.vlt.
  Debug core roles, DMA, barriers, and algorithm correctness.

Step 2: Occamy minimal wrapper
  Bring the kernel into platforms/occamy/target/sim/sw/device/apps.
  Generate a .bin payload.
  Embed it into a host ELF.

Step 3: Occamy host/device validation
  Pass a small host buffer or argument block.
  Confirm device writes the expected result.
  Confirm host sees completion.

Step 4: HeroSDK/OpenMP path
  Only after the lower-level Occamy path works, connect the higher-level
  compiler/runtime/offload machinery.
```

This avoids debugging four unrelated layers at once.

## 18. Why This Matters For FPGA Bring-Up

Before FPGA, pure Snitch can answer:

```text
Is the Snitch kernel itself sane?
```

Occamy simulation can answer:

```text
Is the host/device integration sane?
```

FPGA bring-up should not be the first place to discover either of these are
broken.

For this branch, the useful pre-FPGA evidence is:

```text
M0:
  host can wake device and receive completion

M1:
  host can pass a pointer and device can write host-visible data

M2:
  Occamy can carry a real Snitch-style AXPY payload

M3a:
  real Snitch mailbox manager calls a target in Verilator

M3b:
  HeroSDK/OpenMP software path reaches the Occamy plugin and replay bridge
```

Pure Snitch is still valuable, but it is not a substitute for Occamy when the
next milestone is FPGA bring-up of the heterogeneous system.

## 19. Sources

Official upstream documentation:

```text
Snitch Getting Started
https://pulp-platform.github.io/snitch_cluster/ug/getting_started.html

Snitch Tutorial
https://pulp-platform.github.io/snitch_cluster/ug/tutorial.html
```

Local source files inspected:

```text
platforms/occamy/deps/snitch_cluster/target/snitch_cluster/Makefile
platforms/occamy/deps/snitch_cluster/target/snitch_cluster/sw/Makefile
platforms/occamy/deps/snitch_cluster/target/snitch_cluster/sw/apps/common.mk
platforms/occamy/deps/snitch_cluster/sw/README.md
platforms/occamy/deps/snitch_cluster/sw/blas/axpy/src/main.c
platforms/occamy/target/sim/cfg/single-cluster.hjson
platforms/occamy/target/sim/sw/device/apps/minimal_irq/Makefile
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
platforms/occamy/target/sim/sw/device/apps/roundtrip/Makefile
platforms/occamy/target/sim/sw/device/apps/roundtrip/src/roundtrip.S
platforms/occamy/target/sim/sw/device/apps/blas/axpy/Makefile
platforms/occamy/target/sim/sw/device/apps/common.mk
platforms/occamy/target/sim/sw/device/runtime/src/occamy_device.h
platforms/occamy/target/sim/sw/shared/runtime/heterogeneous_runtime.h
platforms/occamy/target/sim/sw/host/runtime/start.S
platforms/occamy/target/sim/sw/host/runtime/host.c
platforms/occamy/target/sim/sw/host/apps/offload/Makefile
platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
platforms/occamy/target/sim/sw/host/apps/roundtrip/src/roundtrip.c
scripts/run-local-occamy-minimal.sh
```
