# Snitch-Lite Feature Comparison Against Upstream Snitch

This document compares the custom DE1-SoC `SL` Snitch-Lite path against the
original Snitch/Occamy style. It does not describe the newer preferred `U`
Genus/upstream path; see [`TRACKS.md`](TRACKS.md) for that distinction.

It answers three questions for each feature:

```text
1. What do we have locally?
2. How does upstream Snitch or Occamy normally do it?
3. What is the next realistic plan for the DE1-SoC path?
```

The important framing:

```text
Snitch-Lite is not full Occamy.
Snitch-Lite does use the real upstream snitch.sv core.
Snitch-Lite replaces the large upstream cluster/SoC wrapper with a small
Quartus/DE1-SoC wrapper so we can build, synthesize, program, and test it on
the Cyclone V FPGA.
```

## Source Anchors

```text
Local DE1 path:
  fpga/de1-soc/README.md
  fpga/de1-soc/q0_snitch_verilator/
  fpga/de1-soc/sl13_snitch_hps_irq_done/

Local SL13 implementation:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv
  fpga/de1-soc/sl13_snitch_hps_irq_done/scripts/create_qsys.tcl
  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c

Local SL14 implementation:
  fpga/de1-soc/sl14_snitch_hps_irq_linux/driver/snitch_lite_irq.c
  fpga/de1-soc/sl14_snitch_hps_irq_linux/sw/s14_irq_wait_nolibc.c
  fpga/de1-soc/sl14_snitch_hps_irq_linux/scripts/program_and_run.sh
  fpga/de1-soc/sl14_snitch_hps_irq_linux/captures/s14_irq_wait_2026-07-06.txt

Upstream Snitch checkout used by Occamy:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/

Upstream Snitch core:
  .../hw/snitch/src/snitch.sv

Upstream generated cluster target:
  .../target/snitch_cluster/generated/snitch_cluster_wrapper.sv
  .../target/snitch_cluster/test/testharness.sv
  .../target/snitch_cluster/sw/runtime/rtl/src/snrt.h
  .../target/snitch_cluster/sw/runtime/common/snitch_cluster_memory.h

Occamy M0 host/device proof:
  platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S
  platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c
  platforms/occamy/target/sim/sw/host/runtime/host.c
```

## Status Legend

```text
┌───────────┬────────────────────────────────────────────────────────────┐
│ Status    │ Meaning                                                    │
├───────────┼────────────────────────────────────────────────────────────┤
│ done      │ Built and tested locally on the DE1-SoC path.              │
│ partial   │ Local educational equivalent exists, but it is simplified. │
│ not-yet   │ Not implemented locally; good future work.                 │
│ avoid-now │ Possible, but high-friction or low-value right now.        │
└───────────┴────────────────────────────────────────────────────────────┘
```

## High-Level Map

```text
┌─────────────────────────┬─────────┬────────────────────────────────────┐
│ Feature                 │ Local   │ Relationship to upstream Snitch     │
├─────────────────────────┼─────────┼────────────────────────────────────┤
│ Real Snitch core        │ done    │ Same core module, smaller params.   │
│ Full cluster wrapper    │ partial │ Replaced by DE1-specific wrapper.   │
│ Tool flow               │ done    │ Quartus-first, not upstream-native. │
│ Boot/payload loading    │ partial │ Headered small payload, not ELF.     │
│ Host control            │ done    │ HPS/Linux MMIO, simpler than Occamy. │
│ Data input/output       │ done    │ Registers + tiny RAM, not runtime.   │
│ Local memory/TCDM       │ partial │ Tiny RAM, not banked TCDM.           │
│ Done interrupt          │ done    │ SL13 IRQ + SL14 Linux wait pass.      │
│ DMA                     │ not-yet │ Upstream has real DMA machinery.     │
│ Multi-core cluster      │ not-yet │ Upstream is config-generated.        │
│ FPU/SSR/Xfrep features  │ not-yet │ Disabled locally for area/simplicity │
│ Linux driver integration│ done    │ SL14 module passes console + LXDE.   │
└─────────────────────────┴─────────┴────────────────────────────────────┘
```

## Line-Level Study Map

Use this section as the main reading guide. For each feature, read the local
DE1-SoC files first, then read the upstream Snitch/Occamy files listed next to
it. The line numbers are for the current checkout and can drift if the files
are edited later.

### 1. Core Instantiation

What to understand:

```text
Are we using the real Snitch core?
Yes. The local wrapper instantiates upstream snitch.sv directly.
The difference is the configuration around the core.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:1-55
    Local type shims for Snitch data/accelerator interfaces.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:385-449
    Direct instantiation of the real snitch module with small parameters:
    RV32E-style, 32-bit data path, no FPU, no DMA, no SSR, no virtual memory.

Upstream Snitch logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/hw/snitch/src/snitch.sv:13-68
    The upstream snitch module parameters and basic ports.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/hw/snitch/src/snitch.sv:75-110
    Instruction port, accelerator port, TCDM data port, translation, FPU,
    events, and barrier ports.

What to compare:
  Our instantiation sets many upstream options to zero.
  Upstream exposes the same core, but expects a richer environment around it.
```

### 2. Cluster Wrapper And Tool Flow

What to understand:

```text
Upstream Snitch usually builds a generated cluster wrapper.
We replaced that with a smaller Quartus/DE1-SoC wrapper.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:57-70
    Our top-level IP-facing module: clock/reset, Avalon-MM registers, irq, LEDs.

  fpga/de1-soc/sl13_snitch_hps_irq_done/ip/s13_snitch_irq_payload/s13_snitch_irq_payload_hw.tcl:69-103
    Qsys component definition: Avalon-MM slave, LED conduit, interrupt sender.

  fpga/de1-soc/sl13_snitch_hps_irq_done/scripts/create_qsys.tcl:15-37
    HPS instance, lightweight HPS-to-FPGA bridge, and f2h_irq0 connection.

Upstream Snitch logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/README.md:3-16
    Upstream target layout: generated wrapper, bootdata, runtime, tests.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:1-17
    Generated-file warning and generated package start.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:167-181
    Upstream wrapper ports: debug, interrupts, narrow/wide AXI-like ports.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:194-295
    The wrapper instantiates snitch_cluster with generated parameters.

What to compare:
  Our wrapper is board-facing and minimal.
  Upstream wrapper is cluster-facing and generator-produced.
  The core is shared; the wrapper philosophy is different.
```

### 3. Boot And Payload Loading

What to understand:

```text
Our payload path is a tiny raw-word loader.
Upstream uses generated boot data, linker scripts, startup/runtime code, and
ELF-style software flows.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:160-224
    ARM Linux reads /tmp/s13_payload.bin and converts bytes to 32-bit words.

  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:227-258
    ARM writes payload words into FPGA instruction memory through MMIO.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:184-190
    Snitch instruction fetch reads from the local imem_q array.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:240-284
    Hardware accepts host writes to PAYLOAD_WORDS and PAYLOAD[n].

  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/payload_sum.S:1-27
    The tiny Snitch-side payload that gets compiled to /tmp/s13_payload.bin.

Upstream Snitch/Occamy logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/README.md:6-16
    Upstream target says generated contains bootdata and RTL wrapper, and sw
    contains runtime/apps/tests.

  platforms/occamy/target/sim/sw/host/runtime/start.S:66-72
    Occamy M0 host ELF embeds the Snitch payload with .incbin DEVICEBIN.

  platforms/occamy/target/sim/sw/host/runtime/host.c:182-196
    Occamy host programs Snitch entry pointer and communication buffer.

What to compare:
  Our host writes raw instruction words into imem_q.
  Occamy M0 embeds a raw device binary in the host ELF and points Snitch at it.
  Upstream Snitch target has a broader generated boot/runtime flow.
```

### 4. Host Control Path

What to understand:

```text
Our host is ARM Linux on the DE1-SoC HPS.
Occamy M0 host is CVA6 bare-metal software in simulation.
Both perform the same high-level job: prepare, start Snitch, wait for finish.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:31-47
    ARM-side register offsets.

  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:331-350
    ARM opens /dev/mem and maps the lightweight bridge at 0xff200000.

  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:260-328
    One host run: write args, start, poll done, check result, check IRQ state.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:75-95
    Hardware register IDs.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:357-383
    Hardware register readback mux.

Occamy M0 host logic:
  platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c:7-29
    High-level host flow: reset, enable interrupts, program Snitch, wake, wait.

  platforms/occamy/target/sim/sw/host/runtime/host.c:193-230
    Program Snitch entry point and wake clusters.

  platforms/occamy/target/sim/sw/host/runtime/host.c:271-273
    Wait for Snitch completion interrupt and clear host interrupt.

What to compare:
  Our host-control API is explicit MMIO registers.
  Occamy host-control API is runtime helper functions over SoC control/CLINT.
```

### 5. Data Input And Output

What to understand:

```text
Our current data path is small but real:
ARM writes input registers, wrapper copies them into local RAM, Snitch loads
them, computes, stores result, and writes done/result MMIO.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:260-267
    ARM writes ARG0, ARG1, EXPECTED, then CONTROL.start.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:291-305
    On start, hardware clears RAM and copies host_arg0_q/host_arg1_q to RAM0/1.

  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/payload_sum.S:15-24
    Snitch payload loads RAM0/RAM1, adds, stores RAM2, writes done MMIO.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:315-346
    Hardware services Snitch data-port reads/writes to RAM and done MMIO.

Upstream Snitch logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/sw/runtime/rtl/src/snrt.h:10-38
    Runtime includes cluster memory, DMA, interrupts, SSR, sync, team helpers.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/sw/runtime/common/snitch_cluster_memory.h:25-58
    Runtime exposes TCDM start/end, CLINT pointers, barrier address, zero memory.

What to compare:
  Our data path is register plus tiny local RAM.
  Upstream data path is runtime-managed cluster memory and peripherals.
```

### 6. Local RAM Versus Upstream TCDM

What to understand:

```text
Our RAM is a single small memory.
Upstream TCDM is banked, configurable, and part of the cluster architecture.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:102-104
    Local done-MMIO address, RAM base address, RAM word count.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:142-146
    Local RAM and IMEM arrays.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:193-197
    Data request decoding for done MMIO and local RAM.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:333-346
    RAM write strobes from Snitch data-port stores.

Upstream Snitch logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/cfg/default.hjson:19-27
    Configurable TCDM size/banks and DMA FIFO depths.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:212-219
    Generated cluster instantiation sets NrCores, TCDMDepth, NrBanks, DMA FIFO
    depths.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/sw/runtime/common/snitch_cluster_memory.h:25-58
    Runtime view of TCDM and cluster peripheral addresses.

What to compare:
  Our RAM address decode is simple.
  Upstream TCDM is a generated, banked memory subsystem with runtime-visible
  address boundaries.
```

### 7. Done Interrupt And SL13

What to understand:

```text
Our SL13 interrupt is a Snitch-to-HPS done signal.
Upstream also has interrupt inputs into Snitch and cluster-local interrupt
helpers. Occamy M0 has a Snitch-to-host completion interrupt proof.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:91-92
    IRQ_ENABLE and IRQ_PENDING register IDs.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:138-140
    IRQ enable, pending, and output-line state.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:170-171
    irq_line = irq_enable_q && irq_pending_q.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:266-270
    Host writes IRQ_ENABLE and clears IRQ_PENDING.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:327-330
    Snitch done-MMIO write sets result, STATE_DONE, and irq_pending_q.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:373-374
    Host reads IRQ_ENABLE, IRQ_PENDING, and live irq_line.

  fpga/de1-soc/sl13_snitch_hps_irq_done/scripts/create_qsys.tcl:20-21
    HPS f2h interrupt input is enabled.

  fpga/de1-soc/sl13_snitch_hps_irq_done/scripts/create_qsys.tcl:37
    Qsys connects hps_0.f2h_irq0 to snitch_payload.irq.

  fpga/de1-soc/sl13_snitch_hps_irq_done/ip/s13_snitch_irq_payload/s13_snitch_irq_payload_hw.tcl:99-103
    Qsys component declares irq as an interrupt sender.

  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:315-324
    ARM tester checks IRQ asserted and clearable.

  fpga/de1-soc/sl13_snitch_hps_irq_done/sw/s13_irq_nolibc.c:369-373
    ARM tester clears stale pending state and enables IRQ.

Upstream Snitch and Occamy logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/hw/snitch/src/snitch.sv:67-68
    Core-level irq_i input.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/hw/snitch/src/snitch.sv:2242-2254
    irq_i fields become machine interrupt pending signals.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:167-181
    Generated cluster wrapper exposes meip_i, mtip_i, msip_i.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/test/testharness.sv:11-23
    Testbench CLINT DPI path produces msip bits.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/test/testharness.sv:76-87
    Testbench updates msip through clint_tick().

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/sw/snRuntime/src/cluster_interrupts.h:7-21
    Runtime set/clear functions for cluster-local interrupts.

  platforms/occamy/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S:15-25
    Occamy M0 Snitch payload writes 1 to 0x04000000, then parks.

  platforms/occamy/target/sim/sw/host/apps/offload/src/offload.c:12-26
    Occamy host enables interrupts, wakes Snitch, waits for completion.

  platforms/occamy/target/sim/sw/host/runtime/host.c:307-344
    Host-side WFI and software interrupt pending wait.

What to compare:
  snitch.sv irq_i is platform-to-Snitch interrupt input.
  Occamy M0 minimal_irq.S is Snitch-to-host completion signaling.
  Our SL13 is also Snitch-to-host completion signaling, but through a DE1 Qsys
  f2h_irq0 sender and a simple MMIO pending register.
```

### 8. DMA

What to understand:

```text
We do not have DMA yet.
Upstream has DMA-related instructions, runtime helpers, and wide external ports.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:390
    Xdma is disabled in the local Snitch instantiation.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:167-168
    Accelerator response is tied off.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:430-434
    Accelerator request interface is accepted/tied off, not connected to DMA.

Upstream Snitch logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/hw/snitch/src/snitch.sv:2098-2168
    DMA custom instructions are legal only when Xdma is enabled.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/sw/snRuntime/src/dma.h:8-169
    Runtime helpers for 1D/2D DMA start and wait.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:178-181
    Wide AXI-like ports are exposed on the generated wrapper.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/test/testharness.sv:61-74
    Testbench connects wide_out_req to a memory model named i_dma.

What to compare:
  Our next DMA-like step should not start from full upstream DMA.
  First add a local DMA-lite copy engine, then decide whether to connect Snitch
  Xdma instructions.
```

### 9. Multi-Core Cluster

What to understand:

```text
We currently run one Snitch core.
Upstream Snitch clusters are generated around hives, core counts, hart IDs,
TCDM, barriers, and cluster-local interrupts.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:421
    Local Snitch hart_id_i is fixed to 0.

  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:447-449
    Barrier output exists but barrier input is tied off.

Upstream Snitch logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/cfg/default.hjson:48-66
    Default config describes a hive with multiple compute cores and a DMA core.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:19-20
    Generated localparams for NrCores and NrHives.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:212-214
    Generated snitch_cluster parameters set NrHives and NrCores.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/test/testharness.sv:78-85
    Testbench sizes and updates msip for NumCores.

What to compare:
  Our design proves one core plus host control.
  Upstream cluster logic scales core count and interrupt vectors by generated
  configuration.
```

### 10. FPU, SSR, Xfrep, And Extensions

What to understand:

```text
We intentionally disabled these for the DE1 path.
Upstream carries them as first-class generated options.
```

Compare these files:

```text
Our DE1-SoC logic:
  fpga/de1-soc/sl13_snitch_hps_irq_done/rtl/s13_snitch_irq_payload_core.sv:390-405
    Xdma, Xssr, FP_EN, RVF, RVD, extra FP/vector options, VM, and Xipu disabled.

Upstream Snitch logic:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/hw/snitch/src/snitch.sv:22-44
    Core parameters for Xdma, Xssr, FP, RVF/RVD, low-precision/vector options,
    VM, and Xipu.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/hw/snitch/src/snitch.sv:2170-2205
    SSR configuration instructions are legal only when Xssr is enabled.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/generated/snitch_cluster_wrapper.sv:223-249
    Generated wrapper enables RVF/RVD, Xssr, Xfrep, and passes FPU/SSR configs.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/cfg/default.hjson:85-118
    Default compute and DMA core templates list ISA and extension settings.

What to compare:
  Our core uses the small integer subset to make board bring-up tractable.
  Upstream generated configs describe the richer architecture we may selectively
  reintroduce later.
```

### 11. Verification Evidence

What to understand:

```text
Our verification is staged and board-oriented.
Upstream verification is target/testbench/runtime-oriented.
```

Compare these files:

```text
Our DE1-SoC evidence:
  fpga/de1-soc/README.md:68-179
    Stage index and current verified status from D0 through SL13.

  fpga/de1-soc/sl13_snitch_hps_irq_done/README.md:182-214
    SL13 build, timing, board, and runtime checks.

  fpga/de1-soc/sl13_snitch_hps_irq_done/README.md:216-240
    Runtime transcript showing payload load, result, RAM state, IRQ pending.

Upstream Snitch evidence structure:
  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/README.md:3-16
    Upstream target layout with testbench, bootrom, runtime, tests.

  platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b/target/snitch_cluster/test/testharness.sv:25-74
    Testbench instantiates generated cluster wrapper plus memory models.

What to compare:
  Our proof is practical board bring-up.
  Upstream proof is built around generated simulation targets and runtime tests.
```

## 1. Real Snitch Core

Local status: `done`

What we have:

```text
SL3 and later instantiate the real upstream module:

  snitch

from:

  .../hw/snitch/src/snitch.sv

The local wrapper configures it as a very small RV32E-style core:

  BootAddr   = 0x00000000
  AddrWidth  = 33
  DataWidth  = 32
  RVE        = 1
  FP_EN      = 0
  Xdma       = 0
  Xssr       = 0
  VMSupport  = 0
```

How upstream does it:

```text
Upstream Snitch also uses snitch.sv, but normally not alone.
The core is placed inside snitch_cluster, with generated configuration,
instruction cache, TCDM, cluster peripherals, interrupts, optional FPU/SSR/DMA,
AXI ports, and runtime support.
```

What this means:

```text
The CPU core is real.
The surrounding cluster/SoC infrastructure is our reduced educational shell.
```

Plan:

```text
Keep the direct-core path as the DE1-SoC baseline.
Add missing cluster-like features one at a time, instead of trying to port the
full upstream cluster wrapper into Quartus Lite in one jump.
```

## 2. Cluster Wrapper And Tool Flow

Local status: `partial`

What we have:

```text
Q2 tried the upstream-style wrapper path.
Quartus Lite reached real Snitch RTL but failed on advanced SystemVerilog usage
from the upstream dependency stack.

SL3 changed strategy:

  upstream snitch.sv core
      │
      ▼
  small local DE1 wrapper
      │
      ▼
  sv2v / yosys probe
      │
      ▼
  Quartus Lite
      │
      ▼
  DE1-SoC Cyclone V bitstream
```

How upstream does it:

```text
The upstream Snitch target is generated around:

  target/snitch_cluster/generated/snitch_cluster_wrapper.sv

That generated wrapper instantiates:

  snitch_cluster

and exposes AXI-like narrow/wide ports, interrupt inputs, generated package
types, core counts, TCDM parameters, I-cache settings, and extension settings.
```

Why we changed it:

```text
The upstream wrapper is written for a modern ASIC/simulation-style SystemVerilog
flow. It is not carefully split into a small Quartus-friendly FPGA shell.

Trying to translate the full wrapper mechanically is possible in theory, but it
creates many tool and language-compatibility problems before teaching the useful
architecture pieces.
```

Plan:

```text
Do not continue the full wrapper translation as the main path.
Use upstream files as a feature reference.
Rebuild the useful pieces locally in a DE1-compatible way.
```

## 3. Instruction Boot And Payload Loading

Local status: `partial`

What we have:

```text
SL4: fixed tiny instruction ROM.
SL5: generated ROM from a RISC-V assembly payload.
SL6: generated ROM with size and entry checks.
SL11: ARM writes raw instruction words into FPGA instruction memory.
SL12: ARM reads a separate payload file from Linux and loads it into IMEM.
SL13: same file-loaded payload flow, plus done IRQ latch.
SL15: ARM reads a headered payload image and validates metadata before loading.
```

Current local shape:

```text
ARM Linux filesystem
  -> /tmp/s15_payload.img
  -> ARM loader validates SL15 magic/version/header/entry/args/checksum
  -> /dev/mem maps 0xff200000
  -> payload words written to FPGA IMEM window at offset 0x100
  -> CONTROL.start
  -> Snitch fetches from address 0x00000000
```

How upstream does it:

```text
Upstream Snitch target generation creates files such as:

  bootdata.cc
  link.ld
  snitch_cluster_wrapper.sv

The testbench/runtime flow is built around linked ELFs, generated memory maps,
boot data, startup code, and target-specific loaders.

Occamy M0 used a simpler embedded-payload trick:

  host runtime start.S includes DEVICEBIN with .incbin
  host program writes the Snitch entry point
  host wakes Snitch harts
```

Gap:

```text
Our payload now has a small SL15 metadata header.
It still has no ELF loader, no relocation, no sections, no symbol loading, and
no upstream runtime startup.
```

SL15 result:

```text
SL15 adds:

  magic number
  format version
  payload word count
  entry address
  input arguments
  expected result
  checksum

This keeps the educational flow simple while moving closer to a real
host/device payload contract.
```

Plan:

```text
After SL15, the next payload-side improvement would be one of:

  multiple sections
  explicit data-memory initialization
  a descriptor block
  a tiny ELF reader
```

## 4. Host Control

Local status: `done`

What we have:

```text
SL8:
  PC controls Snitch-Lite through USB-Blaster/JTAG System Console.

SL9 and later:
  ARM Linux controls Snitch-Lite through the lightweight HPS-to-FPGA bridge.

Current register path:

  ARM Linux
    -> /dev/mem
    -> 0xff200000 lightweight bridge base
    -> Avalon-MM registers
    -> Snitch-Lite wrapper
    -> real Snitch core
```

How upstream/Occamy does it:

```text
In Occamy M0, the CVA6 host runtime does the host role:

  reset/deisolate system
  enable software interrupts
  program Snitch entry point
  wake Snitch cluster through CLINT/cluster interrupt path
  wait for Snitch completion interrupt
```

Gap:

```text
Our host ABI is simple MMIO registers.
Occamy has a richer runtime and system-level control model.
```

Plan:

```text
Keep the register ABI stable while adding features.
Later, add a small host-side library so tests do not duplicate raw offsets.
```

## 5. Data Input And Output

Local status: `done`

What we have:

```text
SL10:
  ARM writes ARG0, ARG1, EXPECTED.
  Wrapper copies ARG0 and ARG1 into local Snitch RAM before start.
  Snitch loads RAM0/RAM1, computes a result, stores RAM2, and writes done MMIO.

SL11-SL13:
  Same idea, but with host-loaded instruction payloads.
```

How upstream does it:

```text
Upstream Snitch software uses memory maps, TCDM, external memory, runtime
helpers, and eventually offload descriptors or runtime-managed shared state.

Occamy software can pass richer data through shared memory/mailbox/runtime
contracts, depending on the demo.
```

Gap:

```text
Our data ABI is still toy-sized:

  ARG0
  ARG1
  EXPECTED
  RAM0/RAM1/RAM2 readback

It proves host-to-accelerator data movement, not a general offload ABI.
```

Plan:

```text
After SL14/SL15, add a small descriptor in local memory:

  input pointer or offset
  output pointer or offset
  byte count
  command id
  status/result

That is closer to how real host/accelerator software is structured.
```

## 6. Local Memory Versus TCDM

Local status: `partial`

What we have:

```text
SL7 and later add a tiny local RAM:

  base address: 0x00001000
  size:         16 words
  shape:        single simple memory
```

How upstream does it:

```text
Upstream Snitch cluster has TCDM:

  tightly coupled data memory
  configurable size
  configurable number of banks
  interconnect/arbitration
  cluster-local memory map
  cluster peripherals above the TCDM range

The upstream runtime exposes helpers such as:

  snrt_l1_start_addr()
  snrt_l1_end_addr()
  snrt_cluster_clint_set_ptr()
  snrt_cluster_clint_clr_ptr()
```

Gap:

```text
Our RAM proves loads/stores and host-visible state.
It does not prove bank conflicts, multiple ports, multiple cores, or the
real TCDM interconnect.
```

Plan:

```text
SL16 should add a tiny TCDM-like memory:

  2 or 4 banks
  address interleaving
  one Snitch data port first
  clear pass/fail tests for bank selection

Only after that should we consider multiple cores contending for memory.
```

## 7. Done Interrupt: SL13/SL14 Worked Example

Local status: `done`

Why SL13 matters:

```text
Polling STATUS.done works, but real host/accelerator systems usually need an
interrupt-style completion path.
```

What SL13 has locally:

```text
Snitch payload writes DONE_MMIO_ADDR = 0x40000000
  -> local wrapper captures result
  -> local wrapper sets IRQ_PENDING
  -> irq_line = IRQ_ENABLE && IRQ_PENDING
  -> Qsys connects snitch_payload.irq to hps_0.f2h_irq0
  -> ARM Linux verifies pending/clear through MMIO
```

SL13 register behavior:

```text
REG_IRQ_ENABLE:
  bit0 = enable done IRQ output

REG_IRQ_PENDING:
  read bit0 = pending
  read bit1 = enable
  read bit2 = current irq output line
  write bit0 = clear pending
```

How upstream Snitch does related interrupt work:

```text
At the core level:
  snitch.sv has an irq_i input with meip, mtip, msip, mcip, debug-style fields.

At the generated cluster-wrapper level:
  snitch_cluster_wrapper exposes meip_i, mtip_i, msip_i.

At the testbench level:
  target/snitch_cluster/test/testharness.sv has a CLINT-like msip path.

At the runtime level:
  cluster_interrupts.h provides snrt_int_cluster_set() and
  snrt_int_cluster_clr().

At the Occamy M0 demo level:
  minimal_irq.S writes to 0x04000000 to interrupt CVA6 hart 0.
  offload.c enables host interrupts, wakes Snitch, then waits for completion.
```

Important difference:

```text
Upstream Snitch interrupt input:
  host/platform can interrupt Snitch.

Occamy M0 completion proof:
  Snitch writes a host-visible interrupt register to wake the host.

Our SL13:
  Snitch writes local done MMIO; FPGA wrapper asserts HPS f2h_irq0.
```

So SL13 is conceptually close to the Occamy M0 completion proof, not a full copy
of upstream cluster interrupt infrastructure.

What SL14 adds:

```text
Linux registers a real IRQ consumer for f2h_irq0 bit 0.
The ARM userspace process blocks on /dev/snitch_lite_irq.
Snitch completion wakes the blocked process.
The driver acknowledges REG_IRQ_PENDING.
/proc/interrupts shows the registered IRQ increment by two for two Snitch runs.
```

SL14 Linux-visible interrupt consumer result

```text
1. Keep the SL13 hardware IRQ register contract.

2. Use the image-specific Linux IRQ mapping:

     older console image:
       direct Linux IRQ 72

     LXDE Ubuntu image:
       Qsys f2h_irq0 offset 40 -> GIC SPI 40 -> Linux virtual IRQ 131

3. UIO was checked first but is unavailable:

     /dev/uio*: not present
     CONFIG_UIO: not set

4. Build and load a tiny matching kernel module instead:

     snitch_lite_irq.ko
       -> request_irq(72, ...)
       -> expose /dev/snitch_lite_irq
       -> wake read()/poll() waiters
       -> clear REG_IRQ_PENDING bit0

5. Verified on board:

     TEST_RC=0
     RUN0_IRQ_EVENT_COUNT = 1
     RUN1_IRQ_EVENT_COUNT = 2
     console: /proc/interrupts IRQ 72 increments by two
     LXDE:    /proc/interrupts IRQ 131 increments by two
```

## 8. DMA

Local status: `not-yet`

What we have:

```text
No DMA in Snitch-Lite.
All current movement is host MMIO writes into registers or instruction memory.
```

How upstream does it:

```text
Upstream Snitch has an Xdma option and runtime helpers such as:

  snrt_dma_start_1d()
  snrt_dma_start_2d()
  snrt_dma_wait()
  snrt_dma_wait_all()

The generated cluster wrapper also has wide AXI-style ports for DMA/external
memory traffic.
```

Gap:

```text
Our design has no autonomous memory copy engine.
The ARM host manually writes data into the FPGA register/memory window.
```

Plan:

```text
SL18 should start with DMA-lite, not full upstream DMA:

  source offset
  destination offset
  length
  start/done
  copy between two local memory regions

After that, decide whether a Snitch custom DMA instruction path is worth adding.
```

## 9. Multi-Core Cluster

Local status: `not-yet`

What we have:

```text
One Snitch core.
No hive.
No multiple harts.
No shared TCDM contention.
No barrier synchronization between cores.
```

How upstream does it:

```text
Upstream Snitch is config-generated.

The checked generated wrapper in this tree can be generated for small targets.
The default config also shows the larger intended structure:

  one cluster
  multiple compute cores
  optional DMA core
  TCDM banks
  I-cache configuration
  cluster-local peripherals
```

Gap:

```text
Our design proves one real Snitch core can run on DE1-SoC.
It does not prove a Snitch cluster.
```

Plan:

```text
Do not jump directly to a full cluster.

Recommended order:

  SL16: tiny banked memory
  SL17: second simple Snitch core or a tiny helper core
  SL17.1: basic shared-memory synchronization
  SL17.2: tiny software barrier

Only then revisit a real cluster-like wrapper.
```

## 10. FPU, SSR, Xfrep, And Extra Snitch Features

Local status: `not-yet`

What we have:

```text
Disabled locally:

  FP_EN
  RVF
  RVD
  Xssr
  Xdma
  Xfrep-style cluster functionality
  vector/low-precision FP extensions
```

How upstream does it:

```text
Upstream Snitch is designed to enable these features through generated
configuration. The generated cluster wrapper carries parameters for FPU
implementation, SSR configuration, outstanding memory operations, and extension
flags.
```

Why they are disabled locally:

```text
The DE1-SoC path is proving host/control/memory/offload mechanics first.
Adding FPU/SSR before the basic host and memory contract is stable would make
debugging harder and increase area/timing risk.
```

Plan:

```text
Add these only after the small memory and interrupt path is solid.

Most useful first optional feature:
  one simple integer-side custom operation or a tiny copy engine

More expensive later features:
  FPU
  SSR
  real DMA custom instructions
```

## 11. Verification And Evidence

Local status: `done`, but lightweight

What we have:

```text
Each stage documents:

  build commands
  programming commands
  expected output
  verified result
  remaining limitations

SL13 evidence includes:

  payload build pass
  ARM tester build pass
  sv2v pass
  Yosys probe pass
  Qsys generation pass
  Quartus map/fit/assembler/timing pass
  JTAG programming pass
  UART transfer pass
  ARM Linux runtime pass
```

How upstream does it:

```text
Upstream Snitch has target testbenches, generated boot data, runtime libraries,
AXI memory models, CLINT simulation, and software tests.
```

Gap:

```text
Our path is well documented for manual reproduction.
It is not yet a full automated regression suite.
```

Plan:

```text
Add a top-level DE1 smoke-test index:

  what can run without the board
  what needs Quartus only
  what needs USB-Blaster/JTAG
  what needs ARM Linux over UART
```

## Recommended Next Steps

```text
┌──────┬──────────────────────────────┬──────────────────────────────────┐
│ Step │ Name                         │ Why                              │
├──────┼──────────────────────────────┼──────────────────────────────────┤
│ SL14  │ Linux IRQ consumer           │ Done: blocking IRQ wait passes.  │
│ SL15  │ Payload metadata/header      │ Done: headered image test passes.│
│ SL16  │ Tiny TCDM-like banked memory │ Move closer to Snitch cluster.   │
│ SL17  │ Minimal multi-core proof     │ First real cluster-like behavior.│
│ SL18  │ DMA-lite                     │ First autonomous data movement.  │
└──────┴──────────────────────────────┴──────────────────────────────────┘
```

Recommended immediate next step:

```text
SL16: add a tiny TCDM-like banked memory.

Reason:
  SL14's true Linux IRQ wait is now solved with a matching kernel module.
  SL15 cleaned the payload contract without new FPGA hardware.
  The next hardware-side gap versus upstream Snitch is local memory structure:
  our RAM is still one tiny simple memory, not banked TCDM.
```

## What Not To Do Next

```text
Do not try to port full Occamy to DE1-SoC.
Do not restart the full upstream snitch_cluster_wrapper Quartus port as the
main path.
Do not add FPU/SSR/DMA before the memory model and host contracts are cleaner.
```

The practical thesis-quality story is:

```text
We identified that full Occamy targets a different FPGA/software stack.
We preserved the real Snitch core.
We built a DE1-compatible wrapper around it.
We progressively proved control, data, payload loading, and interrupt-style
completion from ARM Linux.
The true Linux blocking interrupt consumer now depends on a different
kernel/module environment.
The practical next local work is to move toward more cluster-like memory and
multi-core behavior.
```
