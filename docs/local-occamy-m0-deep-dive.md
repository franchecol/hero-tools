# Local Occamy M0 Deep Dive

This document explains the `M0` milestone from first principles.  It is written
for a reader who is not already familiar with HeroSDK, Occamy, CVA6, Snitch,
Verilator, memory-mapped registers, or this fork.

For the compact current status and reproduction commands, read the
[Local Occamy Milestone Roadmap](local-occamy-roadmap.md). This file is
intentionally more detailed. Its job is to explain what M0 proves, why the files exist, how the
host and accelerator communicate, how to read the waveforms, and how the work
fits into the branch history.

Use the [M0 Manual Replay](local-occamy-m0-manual-replay.md) when you want to
type every phase. For a focused explanation of the two M0 scripts and the
single-cluster Occamy configuration, read the
[M0 Bootstrap And Runner](local-occamy-m0-bootstrap-runner.md).

For a device-side comparison between the official standalone Snitch tutorial
flow and the way Occamy builds, embeds, starts, and verifies Snitch payloads,
read the
[Device-Side Snitch Comparison](local-occamy-device-side-snitch-comparison.md).

## 1. The One-Sentence Version

M0 proves that a locally built, reduced Occamy simulation can run a CVA6 host
program, wake a Snitch device payload, receive a software interrupt from that
Snitch payload, and exit cleanly.

That is the smallest meaningful heterogeneous proof in this branch.

It is not yet a full HeroSDK OpenMP offload.  It is not yet Linux.  It is not
yet FPGA.  It is the base control path that later milestones depend on.

## 2. Why M0 Exists

The upstream HeroSDK/Occamy story is large:

```text
Linux host application
OpenMP target offload
HeroSDK compiler flow
libomptarget plugin
LibHero runtime
Linux driver
Occamy platform
CVA6 host core
Snitch cluster accelerator
shared memory / mailboxes / interrupts
```

Trying to debug that whole stack at once is not practical.  M0 strips the
problem down to the minimum useful hardware/software question:

```text
Can CVA6 and Snitch talk at all inside a local open-source simulation?
```

M0 answers yes, with a very small program:

```text
┌─────────────────────────────────────────────────────────────┐
│ CVA6 host bare-metal program                                │
│   reset cluster                                             │
│   de-isolate cluster                                        │
│   write Snitch entry address into SoC scratch register      │
│   wake Snitch through cluster-local interrupt register      │
│   wait for host software interrupt                          │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Snitch bare-metal payload                                   │
│   only hart 1 performs work                                 │
│   write 1 to global CLINT MSIP address 0x04000000           │
│   park in WFI                                               │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ CVA6 host sees software interrupt, clears it, exits         │
└─────────────────────────────────────────────────────────────┘
```

That proves the basic control path:

```text
CVA6 host code
  → memory-mapped SoC control registers
  → memory-mapped Snitch cluster interrupt register
  → Snitch core execution
  → memory-mapped global CLINT interrupt register
  → CVA6 host interrupt handling
  → simulator exit
```

## 3. What M0 Does Not Prove

M0 does not prove:

- Linux boot.
- A real `/dev/occamydev--1` endpoint.
- The kernel driver.
- OpenMP `#pragma omp target`.
- LibHero allocation.
- Device-side dynamic memory.
- Host/device virtual memory translation.
- FPGA behavior.
- General coherent shared memory.
- Benchmark speedup.

Those are later milestones.  M0 is deliberately smaller.

The important engineering point is that M0 gives us a known-good baseline. If
M1, M2, M3a, M3b, or FPGA bring-up fails, we can fall back to M0 and ask
whether the most basic host/device wakeup path still works.

## 4. Current Milestone Context

The branch currently records this staged path:

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
  Live mailbox manager invokes and completes a device target in Verilator.

M3b: frozen
  HeroSDK/OpenMP cva6/occamy software proof.
  qemu reaches the Occamy OpenMP plugin.
  captured OpenMP launches can be replayed through Verilator.

M4: next
  Reduced FPGA bring-up with apps/omp/basic/map_tofrom_u32.
```

M0 is still the foundation.  The fact that later milestones exist does not make
M0 obsolete.  M0 remains the simplest proof that the reduced local Occamy
simulation is alive.

## 5. Reproducing M0

From a fresh checkout of this fork branch:

```bash
git clone https://github.com/franchecol/hero-tools.git
cd hero-tools
git switch occamy-minimal-bootstrap
./scripts/bootstrap-local-occamy-minimal.sh
```

The bootstrap command delegates to:

```bash
./scripts/run-local-occamy-minimal.sh minimal_irq
```

The default mode is `minimal_irq`, so these are equivalent once
`platforms/occamy` exists:

```bash
./scripts/run-local-occamy-minimal.sh
./scripts/run-local-occamy-minimal.sh minimal_irq
```

Expected success lines:

```text
[occamy-minimal] success
[occamy-minimal] mode: minimal_irq
[occamy-minimal] host ELF: .../offload-minimal_irq.elf
[occamy-minimal] device binary: .../minimal_irq.bin
[occamy-minimal] host trace: .../trace_hart_00.dasm
[occamy-minimal] device trace: .../logs/trace_hart_00001.dasm
```

The important M0 artifacts are:

```text
platforms/occamy/target/sim/bin/occamy_top.vlt
  Verilated Occamy simulator binary.

platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf
  CVA6 host ELF.  It embeds the Snitch binary.

platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.elf
  Standalone RV32 Snitch ELF before embedding.

platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin
  Raw Snitch payload embedded into the host ELF.

platforms/occamy/target/sim/trace_hart_00.dasm
  CVA6 host execution trace.

platforms/occamy/target/sim/logs/trace_hart_00001.dasm
  Snitch hart 1 execution trace.

platforms/occamy/target/sim/sim.vcd
  Waveform dump for GTKWave, if the simulation was built/run with tracing.
```

On this machine, the observed M0 waveform artifact was:

```text
platforms/occamy/target/sim/sim.vcd
size: about 87 MiB
```

That file is generated and should stay local.  It is not a source file to
commit.

## 6. The Core Files To Read

Read these files in this order.

```text
1. scripts/bootstrap-local-occamy-minimal.sh
2. scripts/run-local-occamy-minimal.sh
3. platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
4. platforms/occamy/target/sim/sw/host/runtime/host.c
5. platforms/occamy/target/sim/sw/shared/platform/generated/occamy_base_addr.h
6. platforms/occamy/target/sim/sw/shared/platform/occamy_memory_map.h
7. platforms/occamy/target/sim/sw/shared/runtime/heterogeneous_runtime.h
8. platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
9. platforms/occamy/target/sim/sw/host/runtime/start.S
10. platforms/occamy/target/sim/sw/host/apps/common.mk
11. platforms/occamy/target/sim/sw/device/apps/minimal_irq/Makefile
12. platforms/occamy/target/sim/Makefile
13. platforms/occamy/target/sim/cfg/single-cluster.hjson
```

Then, only after the software path is clear, read the generated/hardware path:

```text
platforms/occamy/target/sim/src/occamy_top.sv
platforms/occamy/target/sim/src/occamy_soc.sv
platforms/occamy/target/sim/src/occamy_quadrant_s1.sv
platforms/occamy/.bender/git/checkouts/snitch_cluster-*/hw/snitch_cluster/src/snitch_cluster.sv
platforms/occamy/.bender/git/checkouts/snitch_cluster-*/hw/snitch_cluster/src/snitch_cluster_peripheral/snitch_cluster_peripheral.sv
platforms/occamy/.bender/git/checkouts/snitch_cluster-*/hw/snitch/src/snitch.sv
```

## 7. The Two Scripts

### 7.1 `bootstrap-local-occamy-minimal.sh`

The bootstrap script is the fresh-machine entry point:

```text
scripts/bootstrap-local-occamy-minimal.sh
```

Its job is not to implement the simulation itself.  Its job is to make sure the
right source tree is present before the runner starts.

It does this:

```text
1. Check that the command is running inside a hero-tools checkout.
2. Check that scripts/run-local-occamy-minimal.sh exists.
3. Ensure platforms/occamy exists.
4. If missing, clone https://github.com/franchecol/occamy.git.
5. Require branch occamy-minimal-bootstrap.
6. Verify required Occamy-side M0/M1 files exist.
7. Verify the Verilator compatibility changes exist.
8. Exec the runner script.
```

The key settings are:

```bash
OCCAMY_URL="${OCCAMY_URL:-https://github.com/franchecol/occamy.git}"
OCCAMY_BRANCH="${OCCAMY_BRANCH:-occamy-minimal-bootstrap}"
RUNNER="${ROOT_DIR}/scripts/run-local-occamy-minimal.sh"
```

The bootstrap script exists because `platforms/occamy` is not a normal tracked
directory inside `hero-tools`.  It is a platform checkout cloned under the
HeroSDK tree.  For reproducibility, the script has to ensure that the matching
Occamy fork branch is present.

For a more detailed script-by-script explanation, read:

```text
docs/local-occamy-m0-bootstrap-runner.md
```

### 7.2 `run-local-occamy-minimal.sh`

The runner script implements the actual local simulation flow:

```text
scripts/run-local-occamy-minimal.sh
```

For M0, its selected mode is:

```bash
APP_MODE="${1:-minimal_irq}"
```

The M0 mode maps to these paths:

```text
DEVICE_APP_DIR = platforms/occamy/target/sim/sw/device/apps/minimal_irq
HOST_APP_DIR   = platforms/occamy/target/sim/sw/host/apps/offload
HOST_ELF       = .../offload-minimal_irq.elf
DEVICE_BIN     = .../minimal_irq.bin
DEVICE_ELF     = .../minimal_irq.elf
```

The runner does this:

```text
1. Check required host tools:
   python, make, rg, bender, verilator, dtc, bc, gcc, g++, c++, ar, ld.

2. Create or reuse .venv-occamy.

3. Install Python generation dependencies if missing:
   hjson, jsonref, mako, pyyaml, tabulate, jsonschema, setuptools<81.

4. Resolve VERILATOR_ROOT.

5. Resolve the bare-metal RISC-V toolchain prefix.

6. If the host distro provides riscv64-elf-* instead of riscv64-unknown-elf-*,
   create compatibility symlinks under ~/bin.

7. Verify the Occamy Makefile has the Verilator compatibility objects:
   verilated_timing.o and verilated_threads.o.

8. Generate reduced Occamy headers using cfg/single-cluster.hjson.

9. Build the Verilator simulator.

10. Build the minimal Snitch payload.

11. Build the CVA6 host application and embed the Snitch binary.

12. Run platforms/occamy/target/sim/bin/occamy_top.vlt with the host ELF.

13. Verify the host and device traces contain the expected instructions.
```

The runner verifies M0 with trace checks.  That is important.  It does not only
trust that the simulator exited.

For M0 it checks:

```text
device trace contains:
  0x80000524 ... 00732023

host trace contains:
  0x80000464 ... 04000737

host trace also contains:
  0x80000068 ... 00a2a023
```

Those correspond to:

```text
00732023  Snitch store to 0x04000000, raising host software interrupt.
04000737  Host loads the CLINT base address to clear the interrupt.
00a2a023  Host writes to tohost, ending the simulation.
```

## 8. The M0 Host Program

The top-level host source is:

```text
platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
```

The whole M0 host sequence is intentionally tiny:

```c
#include "host.c"

int main() {
    reset_and_ungate_quadrants();
    deisolate_all();
    enable_sw_interrupts();
    program_snitches();
    asm volatile("" ::: "memory");
    wakeup_snitches_cl();
    wait_snitches_done();
    mcycle();
}
```

The sequence means:

```text
reset_and_ungate_quadrants()
  Release the Snitch quadrant from reset and enable its clock.

deisolate_all()
  Allow traffic between the quadrant and the rest of the SoC.

enable_sw_interrupts()
  Enable machine software interrupts on the CVA6 host.

program_snitches()
  Write boot information into SoC scratch registers.

asm volatile("" ::: "memory")
  Compiler barrier.  The scratch writes must not be reordered after wakeup.

wakeup_snitches_cl()
  Write the cluster-local interrupt set register to wake Snitch cores.

wait_snitches_done()
  Execute WFI until CVA6 receives the software interrupt from Snitch.

mcycle()
  Read cycle counter.  main returns 0, then startup code writes to tohost.
```

The source includes `host.c` directly:

```c
#include "host.c"
```

That is unusual in general C projects, but it is common in small bare-metal
test programs because it avoids building a separate runtime library for this
minimal path.

## 9. The Host Runtime Helpers

The helper implementation is:

```text
platforms/occamy/target/sim/sw/host/runtime/host.c
```

The most important global is:

```c
volatile comm_buffer_t comm_buffer __attribute__((aligned(8)));
```

For M0, `comm_buffer` is not used to move payload data.  It is still written
to scratch register 2 because the boot/runtime convention expects a host/device
communication pointer to exist.  M1 uses this field for real data movement.

The most important M0 helper is:

```c
static inline void program_snitches() {
    *soc_ctrl_scratch_ptr(1) = (uintptr_t)snitch_main;
    *soc_ctrl_scratch_ptr(2) = (uintptr_t)&comm_buffer;
}
```

Meaning:

```text
scratch_1 = address of embedded Snitch payload
scratch_2 = address of host communication buffer
```

In the observed local M0 ELF, `nm` shows:

```text
0000000080000508 B comm_buffer
0000000080000510 R snitch_main
```

So the expected scratch values are:

```text
scratch_1_qs = 0x80000510
scratch_2_qs = 0x80000508
```

The wakeup helper is:

```c
static inline void wakeup_cluster(uint32_t cluster_id) {
    *(cluster_clint_set_ptr(cluster_id)) = 511;
}
```

Why `511`?

```text
511 decimal = 0x1ff = binary 111111111
```

The reduced cluster has nine harts from the host-visible cluster interrupt
point of view.  Setting those bits wakes the Snitch-side harts in the cluster.
The M0 payload itself only lets hart 1 perform the interrupt write.

The host waits for completion here:

```c
static inline void wait_snitches_done() {
    wait_sw_interrupt();
    clear_host_sw_interrupt();
}
```

And `wait_sw_interrupt()` is:

```c
static inline void wait_sw_interrupt() {
    do
        wfi();
    while (!sw_interrupt_pending());
}
```

So the host is literally sleeping in `wfi` until the software interrupt pending
bit becomes visible in the local `mip` CSR.

## 10. The M0 Device Payload

The Snitch-side source is:

```text
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
```

The entire payload is:

```asm
_start:
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

Line by line:

```text
csrr a0, mhartid
  Read the hardware thread ID.

li t0, 1
  Use hart 1 as the only active worker for this proof.

bne a0, t0, park
  Every other Snitch hart parks immediately.

li t1, 0x04000000
  Load the global CLINT base address.

li t2, 1
  Prepare software interrupt value.

sw t2, 0(t1)
  Store 1 to 0x04000000, setting host hart 0 MSIP.

fence iorw, iorw
  Ensure the MMIO write is ordered.

wfi; j park
  Park forever after signaling completion.
```

The most important instruction is:

```asm
sw t2, 0(t1)
```

Its machine code in the observed build is:

```text
00732023
```

The device trace confirms that this instruction executed at the embedded
address:

```text
0x80000524 DASM(00732023)
opa: 0x4000000
gpr_rdata_1: 0x1
```

Meaning:

```text
address = 0x04000000
data    = 0x00000001
```

That is the Snitch-to-CVA6 completion signal.

## 11. The Address Map And Registers

M0 depends on a small number of memory-mapped register blocks.

The generated base addresses are in:

```text
platforms/occamy/target/sim/sw/shared/platform/generated/occamy_base_addr.h
```

The key definitions are:

```c
#define SOC_CTRL_BASE_ADDR 0x02000000
#define CLINT_BASE_ADDR    0x04000000
#define QUADRANT_0_CLUSTER_0_TCDM_BASE_ADDR   0x10000000
#define QUADRANT_0_CLUSTER_0_PERIPH_BASE_ADDR 0x10020000
#define QUAD_0_CFG_BASE_ADDR 0x0B000000
```

The helper address calculations are in:

```text
platforms/occamy/target/sim/sw/shared/platform/occamy_memory_map.h
```

The important M0 register addresses are:

```text
0x0B000000
  Quadrant clock enable register.
  Written by reset_and_ungate_quad().

0x0B000004
  Quadrant reset_n register.
  Written by reset_and_ungate_quad().

0x0B000008
  Quadrant isolate register.
  Written by deisolate_all().

0x02000018
  SoC scratch register 1.
  Host writes snitch_main here.
  Observed value: 0x80000510.

0x0200001C
  SoC scratch register 2.
  Host writes &comm_buffer here.
  Observed value: 0x80000508.

0x10020180
  Cluster-local CLINT_SET register.
  Host writes 0x1ff here to wake the Snitch cluster.

0x04000000
  Global CLINT MSIP register.
  Snitch writes 1 here to interrupt CVA6 hart 0.
  Host writes 0 here to clear the interrupt.
```

The generated offset definitions behind those addresses are:

```text
OCCAMY_SOC_SCRATCH_1_REG_OFFSET = 0x18
OCCAMY_SOC_SCRATCH_2_REG_OFFSET = 0x1c
SNITCH_CLUSTER_PERIPHERAL_CL_CLINT_SET_REG_OFFSET = 0x180
CLINT_MSIP_REG_OFFSET = 0x0
OCCAMY_QUADRANT_S1_CLK_ENA_REG_OFFSET = 0x0
OCCAMY_QUADRANT_S1_RESET_N_REG_OFFSET = 0x4
OCCAMY_QUADRANT_S1_ISOLATE_REG_OFFSET = 0x8
```

The key concept is memory-mapped I/O:

```text
volatile uint32_t *p = (volatile uint32_t *)0x04000000;
*p = 1;
```

This is not just a RAM write.  In hardware simulation, that store becomes a bus
transaction routed to a register block.  The register block then changes an
interrupt signal.

## 12. Host ELF, Device Binary, And `snitch_main`

The host startup file is:

```text
platforms/occamy/target/sim/sw/host/runtime/start.S
```

It does normal bare-metal startup work:

```text
1. Clear integer registers.
2. Set stack pointer.
3. Set global pointer.
4. Initialize .bss.
5. Initialize wide scratchpad memory.
6. Enable FPU.
7. Call main().
8. After main returns, write to tohost to end simulation.
```

The M0-specific trick is this section:

```asm
.section .devicebin,"a",@progbits
.globl snitch_main
.align 4
snitch_main:
#ifdef DEVICEBIN
    .incbin DEVICEBIN
#endif
```

That embeds the raw Snitch binary into the host ELF and gives it a symbol name:

```text
snitch_main
```

The build has to know where `snitch_main` lands, because the device payload is
linked as if it will execute from that address.  The host app Makefile handles
that in two stages:

```text
platforms/occamy/target/sim/sw/host/apps/common.mk
```

The key steps are:

```text
1. Build a partial host ELF.
2. Use objdump to find the snitch_main symbol address.
3. Write that address into device build/origin.ld as L3_ORIGIN.
4. Build the device binary at that origin.
5. Build the final host ELF with -DDEVICEBIN=".../minimal_irq.bin".
```

The Makefile rule writes:

```make
L3_ORIGIN = 0x<snitch_main address>;
```

For the observed local M0 build:

```text
comm_buffer = 0x80000508
snitch_main = 0x80000510
tohost = 0x800004c0
```

This explains the host assembly:

```text
80000448: sw a2,24(a4)
  writes 0x80000510 to 0x02000018

8000044a: sw a3,28(a4)
  writes 0x80000508 to 0x0200001c

80000454: sw a4,384(a5)
  writes 0x1ff to 0x10020180

80000468: sw zero,0(a4)
  writes 0 to 0x04000000, clearing host MSIP

80000068: sw a0,0(t0)
  writes to tohost, ending simulation
```

## 13. The Software Timeline

This is the complete M0 control flow:

```text
┌─────┬──────────────────────────────┬───────────────────────────────────────┐
│ No. │ Actor                        │ Event                                 │
├─────┼──────────────────────────────┼───────────────────────────────────────┤
│  1  │ Verilator testbench          │ Loads CVA6 host ELF                   │
│  2  │ CVA6 host                    │ Executes _start in start.S            │
│  3  │ CVA6 host                    │ Initializes .bss and runtime state    │
│  4  │ CVA6 host                    │ Calls main() in offload.c             │
│  5  │ CVA6 host                    │ Resets and ungates quadrant           │
│  6  │ CVA6 host                    │ De-isolates quadrant                  │
│  7  │ CVA6 host                    │ Enables machine software interrupt    │
│  8  │ CVA6 host                    │ Writes snitch_main to scratch_1       │
│  9  │ CVA6 host                    │ Writes &comm_buffer to scratch_2      │
│ 10  │ CVA6 host                    │ Writes 0x1ff to cluster CLINT_SET     │
│ 11  │ Snitch cluster               │ Wakes from WFI                        │
│ 12  │ Snitch boot path             │ Jumps to address from scratch_1       │
│ 13  │ Snitch hart 1                │ Executes minimal_irq.S                │
│ 14  │ Snitch hart 1                │ Writes 1 to 0x04000000                │
│ 15  │ Global CLINT                 │ Sets host MSIP                        │
│ 16  │ CVA6 host                    │ Wakes from WFI                        │
│ 17  │ CVA6 host                    │ Clears 0x04000000                     │
│ 18  │ CVA6 host                    │ Returns from main                     │
│ 19  │ CVA6 startup code            │ Writes to tohost                      │
│ 20  │ Verilator testbench          │ Ends simulation                       │
└─────┴──────────────────────────────┴───────────────────────────────────────┘
```

The same flow as a datapath diagram:

```text
┌────────────────────┐
│ CVA6 host _start   │
└─────────┬──────────┘
          ▼
┌────────────────────┐
│ offload.c main()   │
└─────────┬──────────┘
          │ reset, clock, de-isolate
          ▼
┌────────────────────┐
│ Quadrant cfg regs  │  0x0B000000, 0x0B000004, 0x0B000008
└─────────┬──────────┘
          │ program boot pointers
          ▼
┌────────────────────┐
│ SoC scratch regs   │  scratch_1 = snitch_main
│                    │  scratch_2 = &comm_buffer
└─────────┬──────────┘
          │ wake cluster
          ▼
┌────────────────────┐
│ Cluster CLINT_SET  │  0x10020180 = 0x1ff
└─────────┬──────────┘
          │ interrupt into Snitch cluster
          ▼
┌────────────────────┐
│ Snitch hart 1      │  sw 1, 0(0x04000000)
└─────────┬──────────┘
          │ global CLINT MSIP
          ▼
┌────────────────────┐
│ CVA6 host MSIP     │  host wakes from WFI
└─────────┬──────────┘
          │ clear interrupt, return 0
          ▼
┌────────────────────┐
│ tohost             │  simulator exits
└────────────────────┘
```

## 14. How To Read The Host Trace

The host trace is:

```text
platforms/occamy/target/sim/trace_hart_00.dasm
```

Important markers:

```text
0x80000418
  main() starts.

0x80000448
  Host writes snitch_main to SoC scratch register 1.

0x8000044a
  Host writes &comm_buffer to SoC scratch register 2.

0x80000454
  Host writes 0x1ff to cluster CLINT_SET.

0x80000458
  Host executes WFI and waits.

0x80000464
  Host begins CLINT clear path after software interrupt is pending.

0x80000468
  Host writes 0 to 0x04000000 to clear MSIP.

0x80000068
  Startup code writes to tohost to end simulation.
```

The runner checks for:

```text
0x80000464 ... 04000737
0x80000068 ... 00a2a023
```

In the observed local trace:

```text
trace_hart_00.dasm:111: 0x80000464 M (0x04000737) DASM(04000737)
trace_hart_00.dasm:121: 0x80000068 M (0x00a2a023) DASM(00a2a023)
```

The `tohost` marker matters because it proves the host did not merely wake.  It
woke, cleared the interrupt, returned from `main`, and reached the simulation
exit path.

## 15. How To Read The Device Trace

The Snitch hart 1 trace is:

```text
platforms/occamy/target/sim/logs/trace_hart_00001.dasm
```

Important markers:

```text
0x80000510
  Embedded snitch_main starts.

0x80000510
  csrr a0,mhartid.

0x80000514
  li t0,1.

0x80000518
  branch if not hart 1.

0x8000051c
  load CLINT base 0x04000000.

0x80000520
  load value 1.

0x80000524
  store 1 to 0x04000000.

0x8000052c
  park in WFI.
```

The runner checks for:

```text
0x80000524 ... 00732023
```

In the observed local trace:

```text
0x80000524 DASM(00732023)
opa: 0x4000000
gpr_rdata_1: 0x1
is_store: 0x1
```

Interpretation:

```text
Snitch executed the store instruction.
The store address was 0x04000000.
The stored value was 1.
That is the host interrupt.
```

Other Snitch harts should mostly park because the assembly only allows hart 1
to do the MMIO write.

## 16. Waveform-Based Explanation

The waveform file is:

```text
platforms/occamy/target/sim/sim.vcd
```

Open it with:

```bash
gtkwave platforms/occamy/target/sim/sim.vcd
```

If the left signal tree looks like a long list of packages such as
`ariane_pkg`, `axi_pkg`, `occamy_pkg`, `snitch_pkg`, and so on, those are not
the first place to look.  Expand the real instance tree:

```text
TOP
└── testharness
    └── i_occamy
        ├── i_clint
        ├── i_soc_ctrl
        └── i_occamy_soc
            ├── i_occamy_cva6
            └── i_occamy_quadrant_s1_0
                └── i_occamy_cluster_0
                    └── i_cluster
                        ├── i_snitch_cluster_peripheral
                        └── gen_core[0]
                            └── i_snitch_cc
                                └── i_snitch
```

Useful signals to add:

```text
Global:
  TOP.clk_i
  TOP.rst_ni

Host CVA6 progress:
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_cva6.i_cva6.i_cva6.pc_commit
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_cva6.i_cva6.i_cva6.commit_ack
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_cva6.i_cva6.i_cva6.csr_regfile_i.wfi_q

SoC scratch registers:
  TOP.testharness.i_occamy.i_soc_ctrl.i_soc_ctrl.scratch_1_we
  TOP.testharness.i_occamy.i_soc_ctrl.i_soc_ctrl.scratch_1_wd
  TOP.testharness.i_occamy.i_soc_ctrl.i_soc_ctrl.scratch_1_qs
  TOP.testharness.i_occamy.i_soc_ctrl.i_soc_ctrl.scratch_2_we
  TOP.testharness.i_occamy.i_soc_ctrl.i_soc_ctrl.scratch_2_wd
  TOP.testharness.i_occamy.i_soc_ctrl.i_soc_ctrl.scratch_2_qs

Cluster wakeup:
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.i_snitch_cluster_peripheral.i_snitch_cluster_peripheral_reg_top.cl_clint_set_we
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.i_snitch_cluster_peripheral.i_snitch_cluster_peripheral_reg_top.cl_clint_set_wd

Snitch execution:
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.pc_q
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.inst_addr_o
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.inst_data_i
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.wfi_q

Snitch store:
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.i_snitch_lsu.lsu_qwrite_i
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.i_snitch_lsu.lsu_qaddr_i
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.i_snitch_lsu.lsu_qdata_i
  TOP.testharness.i_occamy.i_occamy_soc.i_occamy_quadrant_s1_0.i_occamy_cluster_0.i_cluster.gen_core[0].i_snitch_cc.i_snitch.i_snitch_lsu.lsu_qvalid_i

Host CLINT:
  TOP.testharness.i_occamy.i_clint.i_clint_reg_top.msip_p_0_we
  TOP.testharness.i_occamy.i_clint.i_clint_reg_top.msip_p_0_wd
  TOP.testharness.i_occamy.i_clint.i_clint_reg_top.msip_p_0_qs
  TOP.testharness.i_occamy.msip
  TOP.testharness.i_occamy.i_occamy_soc.msip_i
```

The expected wave sequence is:

```text
1. CVA6 executes host main.

2. scratch_1_we pulses.
   scratch_1_wd should be 0x80000510.
   scratch_1_qs should become 0x80000510.

3. scratch_2_we pulses.
   scratch_2_wd should be 0x80000508.
   scratch_2_qs should become 0x80000508.

4. cl_clint_set_we pulses.
   cl_clint_set_wd should be 0x000001ff.

5. Snitch pc_q reaches the embedded payload region.
   The key instruction is at 0x80000524.

6. Snitch LSU performs a write.
   lsu_qwrite_i = 1.
   lsu_qaddr_i = 0x04000000.
   lsu_qdata_i = 0x00000001.

7. CLINT msip_p_0_qs goes from 0 to 1.

8. CVA6 WFI ends because machine software interrupt is pending.

9. CVA6 clears MSIP.
   msip_p_0_qs goes from 1 to 0.

10. CVA6 writes to tohost and the simulation exits.
```

If you want a tight waveform view, add only these first:

```text
scratch_1_qs
scratch_2_qs
cl_clint_set_wd
Snitch pc_q
Snitch lsu_qwrite_i
Snitch lsu_qaddr_i
Snitch lsu_qdata_i
msip_p_0_qs
CVA6 wfi_q
```

Then zoom around the moment where Snitch `lsu_qwrite_i` pulses.  That is the
center of the M0 proof.

## 17. The Hardware Path Behind The Wave

The high-level RTL path is:

```text
occamy_top.sv
  instantiates:
    occamy_soc
    clint
    occamy_soc_ctrl

occamy_soc.sv
  connects:
    CVA6 host
    S1 quadrant
    msip interrupt wires

occamy_quadrant_s1.sv
  instantiates:
    occamy_cluster_wrapper

snitch_cluster.sv
  instantiates:
    Snitch cores
    Snitch cluster peripheral

snitch_cluster_peripheral.sv
  implements:
    cluster-local CLINT set/clear logic

snitch.sv
  exposes:
    instruction address
    PC
    WFI state
    load/store unit request signals
```

For M0, the most important RTL concept is that the CLINT produces software
interrupt wires:

```text
Snitch store to 0x04000000
  → AXI/regbus transaction into CLINT
  → CLINT register msip_p_0 becomes 1
  → CLINT output ipi_o drives msip
  → occamy_soc receives msip_i
  → CVA6 receives machine software interrupt
```

The host-to-Snitch wakeup path is similar:

```text
CVA6 store to 0x10020180
  → address decode to cluster peripheral
  → cl_clint_set register sees 0x1ff
  → cluster interrupt bits are set
  → Snitch cores leave WFI
```

The software-visible write is ordinary C:

```c
*(cluster_clint_set_ptr(cluster_id)) = 511;
```

The hardware effect is interrupt state changing inside the Snitch cluster
peripheral.

## 18. Why The Single-Cluster Config Matters

The reduced config is:

```text
platforms/occamy/target/sim/cfg/single-cluster.hjson
```

Key settings:

```text
nr_s1_quadrant: 1
s1_quadrant.nr_clusters: 1
cluster.cluster_base_addr: 0x10000000
cluster.cluster_base_offset: 0x40000
cluster.cluster_base_hartid: 1
cluster.tcdm.size: 128 KiB
```

The purpose of this config is practical:

```text
Full Occamy is too large for fast local bring-up.
M0 only needs one CVA6 host and one Snitch cluster.
Reducing the platform makes Verilator build and execution feasible locally.
```

This does not mean the full platform is unimportant.  It means full-platform
debugging is the wrong first step.

## 19. Why Verilator Needed Work

The upstream Occamy simulation path has stronger assumptions than this local
branch wants to make.  It includes flows for commercial simulators and a larger
platform configuration.  The local goal was:

```text
open-source Verilator
single-cluster Occamy
small bare-metal host/device proof
repeatable from a normal Linux checkout
```

The M0 work needed:

```text
1. A reduced Occamy config.
2. Verilator invocation with --timing.
3. Verilator support objects in the link:
   verilated_timing.o
   verilated_threads.o
4. C++ flags compatible with the generated model:
   -include cstdint
   -fcoroutines
5. A tiny Snitch payload.
6. A host build path that embeds that payload.
7. Trace checks that prove the right events happened.
```

That is why the bootstrap script verifies these strings in the Occamy Makefile:

```text
verilated_timing.o
verilated_threads.o
```

If those are missing, the local branch is probably not using the matching
Occamy fork.

## 20. Debugging That Happened During M0

The important debugging lessons were:

```text
The upstream docs were not enough for this exact local goal.
  They describe the broader HeroSDK/Occamy project, not a minimal local
  single-cluster Verilator proof.

platforms/occamy had to be treated as its own checkout.
  Editing Occamy through hero-tools alone was not clean because it is a
  platform repository cloned under platforms/.  The clean solution was a
  matching Occamy fork branch.

The bootstrap had to verify branch content.
  If someone clones hero-tools but has the wrong platforms/occamy checkout,
  the scripts should fail early with a useful error.

Toolchain prefixes differ by distro.
  Arch commonly provides riscv64-elf-* while the Occamy Makefiles expect
  riscv64-unknown-elf-*.  The runner maps compatible tools through ~/bin.

Verilator root detection had to be explicit.
  The runner resolves VERILATOR_ROOT and exports VLT_ROOT so the Occamy build
  can find Verilator include sources.

A successful simulator exit was not enough.
  The runner verifies host and device traces to confirm the actual interrupt
  path happened.

GTKWave was useful after the trace proof.
  The traces prove the instruction-level story.  The VCD proves the signal-level
  story.
```

This is why M0 is more than "we ran a script."  The script now captures several
environment and source assumptions that were previously implicit.

## 21. Improvements Added For M0

The M0-related improvements are:

```text
In hero-tools:
  scripts/bootstrap-local-occamy-minimal.sh
  scripts/run-local-occamy-minimal.sh
  README branch note
  LOCAL_OCCAMY documentation

In the matching Occamy fork:
  target/sim/cfg/single-cluster.hjson
  target/sim/sw/device/apps/minimal_irq/
  target/sim/sw/host/apps/offload support for minimal_irq
  Verilator Makefile compatibility updates
```

Behavioral improvements:

```text
Fresh clone can fetch the expected Occamy fork.
Wrong Occamy checkout is detected.
Missing M0 files are detected.
Missing tools are reported clearly.
Different RISC-V tool prefixes are handled.
The Verilator build uses a reduced platform.
The M0 run is checked through traces.
```

The result is a small, repeatable baseline rather than a one-off local hack.

## 22. Branch Commit History

The current `hero-tools` branch history relative to `main` is:

```text
40b6e28 Add minimal Occamy bootstrap flow
9788907 Document minimal Occamy branch usage
687e340 Clarify minimal branch prerequisites
5246873 Add minimal Occamy status and milestones
ffd06fa Add roundtrip local Occamy bootstrap flow
f9304d2 Simplify Occamy bootstrap to forked setup flow
33ca7e8 Add axpy M2 probe and fix LLVM bootstrap scripts
4b77d8d Improve LLVM bootstrap for minimal M2 builds
2c05666 toolchain: fix local occamy axpy flow
118eef0 docs: update local occamy milestone notes
2dfedad build: detect live Buildroot Linux tuple
bc073c9 build: enable occamy OpenMP build proof
6e0c785 test: add occamy OpenMP runtime smoke
ca34126 test: add occamy fake-driver target launch smoke
2131a13 test: add occamy fake mailbox completion smoke
e975b1d test: add occamy OpenMP mailbox runtime smoke
2ffb850 test: capture occamy OpenMP launch packets
4d16a62 test: dump occamy OpenMP replay snapshots
dc562cb test: add occamy OpenMP replay harness
06f39c5 test: replay captured occamy OpenMP launch
e68f99a docs: record occamy OpenMP replay spot checks
ad80fdd test: replay all captured occamy OpenMP launches
20b7b2c test: add occamy OpenMP replay bridge
798ff80 test: apply replay bridge copyback writes
d84e5ab docs: record full occamy bridge copyback run
2ee329b docs: prepare occamy fpga bringup probe
fea4b99 docs: consolidate local occamy guide
536e82e docs: clarify clean-machine occamy reproduction
4bbca91 build: pin cva6 sdk fork for occamy
```

For M0 specifically, the earliest commits are the most relevant:

```text
40b6e28
  Introduced the minimal Occamy bootstrap flow.

9788907
  Added branch usage documentation.

687e340
  Clarified prerequisites for new machines.

5246873
  Added milestone/status framing.
```

Then M1 was added:

```text
ffd06fa
  Added roundtrip local Occamy bootstrap flow.
```

And the branch later grew into M2/M3a/M3b:

```text
33ca7e8 and later
  Added axpy, HeroSDK/OpenMP build proof, fake driver smoke tests,
  captured launch replay, replay bridge, copyback writes, and documentation.
```

The matching `occamy` fork branch has this observed branch history:

```text
2ffef40 test: add OpenMP mailbox runtime smoke
4623aa9 build: make libomptarget device default buildable
37d6e7c sim: fix axpy builtins library path
2a5dc0c Add minimal local Verilator simulation proofs
39b4a35 fpga: Bootmode to PCIe and device tree to PCIe
```

For M0, the key Occamy-side commit is:

```text
2a5dc0c Add minimal local Verilator simulation proofs
```

That is where the reduced simulator payloads and local Verilator proof became
part of the matching Occamy branch.

## 23. Relationship To M1

M0 proves the control path:

```text
host writes registers
host wakes Snitch
Snitch writes interrupt register
host wakes and exits
```

M1 proves the first real data path:

```text
host creates a 16-word buffer
host stores the buffer pointer in comm_buffer.usr_data_ptr
host passes &comm_buffer through scratch_2
Snitch reads the pointer
Snitch increments the 16 words
Snitch interrupts host
host validates the modified buffer
```

The M1 host source is:

```text
platforms/occamy/target/sim/sw/host/apps/roundtrip/src/roundtrip.c
```

The key line is:

```c
comm_buffer.usr_data_ptr = (uint32_t)(uintptr_t)&roundtrip_buffer[0];
```

The M1 device source is:

```text
platforms/occamy/target/sim/sw/device/apps/roundtrip/src/roundtrip.S
```

The key device behavior is:

```text
load comm_buffer pointer from scratch_2
load usr_data_ptr from comm_buffer
loop over 16 words
load, increment, store
interrupt host
```

So the conceptual progression is:

```text
M0: Can the two sides wake and interrupt each other?
M1: Can the device modify host-provided memory and have the host verify it?
```

## 24. Relationship To M2, M3a, And M3b

M2, M3a, and M3b add more HeroSDK-shaped machinery.

M2:

```text
Uses the reduced local Occamy simulation.
Builds a more realistic RV32 device payload through the HeroSDK LLVM path.
Exercises the existing Occamy AXPY software path.
Still runs as a reduced local simulation proof.
```

M3a:

```text
Runs the real Snitch mailbox manager in Verilator.
Receives a target function address and argument pointer.
Calls the target and returns a checked result and completion code.
```

M3b:

```text
Builds the HeroSDK/OpenMP cva6/occamy software stack.
Uses qemu-riscv64 for the Linux host application path.
Reaches the Occamy OpenMP plugin.
Uses fake driver and replay infrastructure because the local machine has no
real /dev/occamydev--1 endpoint.
Replays captured OpenMP launches through Verilator.
```

M0 matters to M3a and M3b because the later mailbox and OpenMP paths
eventually rely on the same
kinds of operations:

```text
write boot/control registers
write mailbox pointers
wake Snitch
wait for completion
copy data back
clear interrupts
```

M3a automates the mailbox-managed target launch. M3b generalizes it into the
Linux/OpenMP replay flow. M0 exposes the underlying control pattern in its
simplest form.

## 25. Common Misunderstandings

### "Did M0 use HeroSDK OpenMP?"

No.  M0 is bare-metal host plus bare-metal device payload.  It uses files that
live inside the HeroSDK/Occamy tree, but it does not use OpenMP offload.

That is intentional.  M0 answers a lower-level question first.

### "Is the Snitch payload a normal function call?"

No.  The host does not call a Snitch function directly.  The host writes the
device entry address into a scratch register and then wakes the cluster.

The Snitch-side boot path reads that entry address and jumps to it.

### "Is 0x04000000 RAM?"

No.  In this proof, `0x04000000` is the CLINT MSIP register address.  A store
to that address changes interrupt state.

### "Why does only hart 1 do the write?"

The M0 payload uses hart 1 to keep the proof deterministic.  Other Snitch harts
park in WFI.  That avoids multiple harts racing to write the same completion
register.

### "Why does the host write 0x1ff to wake the cluster?"

`0x1ff` has nine low bits set.  The reduced cluster has nine visible cluster
interrupt targets in this path.  The M0 payload still lets only hart 1 perform
the completion write.

### "Why are there both traces and waveforms?"

They answer different questions:

```text
Trace:
  Did the expected instructions execute?

Waveform:
  Did the expected hardware signals and registers change?
```

The trace is faster to check automatically.  The waveform is better for
understanding and debugging hardware timing.

### "Why not go directly to FPGA after M0?"

M0 is too small to justify jumping directly to larger workloads on FPGA.  The
better path is staged:

```text
M0 control path
M1 data path
M2 runtime-shaped local workload
M3a live mailbox-runtime proof
M3b HeroSDK/OpenMP software proof
M4 tiny FPGA map(tofrom) proof
```

Each stage narrows the debug surface of the next one.

## 26. What To Check When M0 Fails

Use this order.

```text
1. Wrong branch?
   git status --short --branch
   git -C platforms/occamy status --short --branch

2. Missing platform checkout?
   ls platforms/occamy

3. Wrong Occamy fork?
   git -C platforms/occamy remote -v
   git -C platforms/occamy branch --show-current

4. Missing Verilator compatibility changes?
   rg 'verilated_timing.o|verilated_threads.o' platforms/occamy/target/sim/Makefile

5. Missing local dependencies?
   command -v verilator
   command -v bender
   command -v dtc
   command -v rg

6. RISC-V tool prefix mismatch?
   command -v riscv64-unknown-elf-gcc
   command -v riscv64-elf-gcc

7. Simulator missing?
   ls platforms/occamy/target/sim/bin/occamy_top.vlt

8. Host ELF missing?
   ls platforms/occamy/target/sim/sw/host/apps/offload/build/offload-minimal_irq.elf

9. Device binary missing?
   ls platforms/occamy/target/sim/sw/device/apps/minimal_irq/build/minimal_irq.bin

10. Trace proof missing?
   rg '0x80000524.*00732023' platforms/occamy/target/sim/logs/trace_hart_00001.dasm
   rg '0x80000464.*04000737' platforms/occamy/target/sim/trace_hart_00.dasm
   rg '0x80000068.*00a2a023' platforms/occamy/target/sim/trace_hart_00.dasm
```

If the simulator runs but the trace checks fail, the run is not a valid M0
success.  The trace checks are part of the proof.

## 27. Why M0 Is Important

M0 is important because it establishes the lowest-level facts that every later
stage depends on:

```text
The reduced Occamy RTL can be generated.
The reduced Occamy RTL can be Verilated.
The Verilated simulator can run locally.
CVA6 can execute a host ELF.
The host ELF can embed a Snitch payload.
CVA6 can program SoC scratch registers.
CVA6 can wake the Snitch cluster.
Snitch can execute the embedded payload.
Snitch can perform a memory-mapped write to the global CLINT.
CVA6 can observe and clear the software interrupt.
The testbench can observe tohost and end cleanly.
```

Without those facts, failures in OpenMP, LibHero, Linux, qemu, driver mapping,
mailboxes, or FPGA would be much harder to localize.

M0 is not the final goal.  It is the first stable coordinate in the project.

## 28. Summary

M0 is a minimal heterogeneous control-path proof:

```text
CVA6 host
  writes Snitch entry and comm buffer pointers
  wakes Snitch cluster
  waits in WFI

Snitch hart 1
  executes a tiny embedded payload
  writes 1 to global CLINT MSIP at 0x04000000
  parks

CVA6 host
  receives software interrupt
  clears MSIP
  writes to tohost
  exits simulation
```

The most important source files are:

```text
scripts/bootstrap-local-occamy-minimal.sh
scripts/run-local-occamy-minimal.sh
platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
platforms/occamy/target/sim/sw/host/runtime/host.c
platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
platforms/occamy/target/sim/sw/host/runtime/start.S
platforms/occamy/target/sim/sw/shared/platform/occamy_memory_map.h
platforms/occamy/target/sim/sw/shared/platform/generated/occamy_base_addr.h
```

The most important registers are:

```text
0x02000018  SoC scratch_1, Snitch entry pointer
0x0200001C  SoC scratch_2, comm_buffer pointer
0x10020180  cluster CLINT_SET, Snitch wakeup
0x04000000  global CLINT MSIP, host software interrupt
```

The most important observed values are:

```text
snitch_main  = 0x80000510
comm_buffer  = 0x80000508
CLINT_SET    = 0x000001ff
host MSIP    = 0x00000001 then 0x00000000
```

The most important proof markers are:

```text
Device trace:
  0x80000524 ... 00732023

Host trace:
  0x80000464 ... 04000737
  0x80000068 ... 00a2a023
```

When those are present, M0 has done what it was designed to do.
