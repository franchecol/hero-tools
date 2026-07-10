# Snitch-Lite SL3: Core-Only Probe

SL3 starts the next path after the Q2.1 translation experiment.

Q2 tried to package the full generated `snitch_cluster_wrapper` for Quartus.
Q2.1 showed that translating the full cluster through `sv2v` is not a good path
for DE1-SoC: the full target pulls in too much AXI, cluster, assertion, and
tech-cell SystemVerilog.

SL3 therefore reduces the scope:

```text
Do not instantiate snitch_cluster_wrapper.
Instantiate the real snitch core directly.
Provide small local package shims for the types needed by that core.
Probe the smaller subset with sv2v/yosys first.
```

## What This Project Is

```text
rtl/snitch_core_shims.sv
  Minimal local package definitions for this probe:
    dm
    fpnew_pkg
    reqrsp_pkg

rtl/de1_s3_snitch_core_probe.sv
  Thin DE1 top that instantiates the real upstream snitch module with most
  optional features disabled.

scripts/run_sv2v_probe.sh
  Converts only the smaller Snitch-core subset with sv2v, then asks yosys to
  parse/check the translated Verilog if conversion succeeds.

scripts/export_quartus_project.sh
  Regenerates the translated Verilog and writes a minimal Quartus project that
  uses generated/snitch_core_probe.v as its only RTL input.

scripts/quartus_preflight.sh
  Runs Quartus analysis/elaboration on the generated project.

scripts/build.sh
  Runs the full Quartus compile flow and produces a .sof if successful.
```

The runner creates one generated source copy:

```text
generated/snitch_synthesis_probe.sv
```

That copy removes only upstream `pragma translate_off/on` debug-only blocks
before `sv2v`. This avoids Yosys parsing simulation-only tasks such as
`$bitstoshortreal` while keeping the upstream checkout untouched.

## What This Project Is Not

```text
Not a full SoC yet.
Not a full Snitch cluster.
Not a replacement for Q0/Q1 simulation.
Not a board-programmable LED demo yet.
```

At this stage, SL3 is a feasibility probe. If the reduced core subset can pass
translation/parsing, the next step is to add simple ROM/RAM/MMIO around it.

## Run

Translation and Yosys structural check:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl3_snitch_core_only_probe
./scripts/run_sv2v_probe.sh
```

Quartus analysis/elaboration:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl3_snitch_core_only_probe
./scripts/quartus_preflight.sh
```

Full Quartus compile:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl3_snitch_core_only_probe
./scripts/build.sh
```

The generated outputs are ignored by git and written under:

```text
generated/
```

## Expected Interpretation

```text
If sv2v fails:
  The first error tells us which remaining core-level construct must be reduced,
  shimmed, or avoided.

If sv2v passes but yosys fails:
  The translation completed, but the generated Verilog still has parser or
  elaboration issues.

If both pass:
  The smaller core-only path is viable enough to try a Quartus preflight.
```

## Verified Result

Verified locally on 2026-07-02:

```text
sv2v:
  PASS
  The reduced Snitch-core subset converts to generated/snitch_core_probe.v.

yosys:
  PASS
  The translated Verilog parses, elaborates with top
  de1_s3_snitch_core_probe, lowers processes, and passes check.

Quartus analysis/elaboration:
  PASS
  Quartus accepts the translated core-only Verilog project.

Quartus full compile:
  PASS
  Quartus produces:
    generated/output_files/de1_s3_snitch_core_probe.sof
```

Commands:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl3_snitch_core_only_probe
./scripts/run_sv2v_probe.sh
./scripts/quartus_preflight.sh
./scripts/build.sh
```

Important meaning:

```text
This proves:
  A real upstream snitch.sv instance can be reduced enough for sv2v/yosys.
  The DE1 path should continue with the core-only shell, not the full cluster.
  Quartus can compile the translated SL3 shell and generate a .sof.

This does not yet prove:
  The core can fetch from ROM/RAM.
  The board LEDs/UART/MMIO are driven by actual Snitch software.
  The full core resource cost is represented.
```

Quartus resource result for this SL3 shell:

```text
Logic utilization:       13 / 32,070 ALMs (< 1 %)
Registers:               25
Block memory bits:       0
DSP blocks:              0
Worst setup slack:       17.436 ns on CLOCK_50
Worst hold slack:        0.189 ns on CLOCK_50
Full compile status:     0 errors, 73 warnings
```

That small resource count is expected for SL3 and must not be overinterpreted:

```text
The instruction input is still a constant NOP.
There is no ROM, RAM, bus, or real software image.
Quartus can optimize away most unused core behavior.
SL3 is a toolchain acceptance proof, not a final Snitch utilization number.
```

## Why This Is The Next Best Step

The full cluster path failed because it drags in broad infrastructure:

```text
AXI fabrics
DMA/future blocks
cluster wrapper
tech-cell primitive files
assertion/property syntax
complex package features
```

The core-only path deliberately starts from the smallest useful real Snitch
artifact:

```text
snitch.sv
snitch_lsu.sv
snitch_l0_tlb.sv
snitch_regfile_ff.sv
minimal packages and FIFO dependency
```

That keeps the educational target aligned with the DE1-SoC board:

```text
one real RISC-V accelerator core
simple local memory/peripheral shell
eventually LEDs/UART/MMIO
```

## Next Step

Move from probe to hardware shell:

```text
SL4 candidate:
  add tiny instruction ROM
  add tiny data RAM or fixed MMIO response
  make Snitch execute a minimal instruction sequence
  expose one core-visible event on LEDR
```

The first board-visible goal should stay small:

```text
Snitch fetches instructions -> performs one store/load/event -> LED changes
```
