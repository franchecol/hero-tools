# Snitch-Lite S3: Core-Only Probe

S3 starts the next path after the S2.1 translation experiment.

S2 tried to package the full generated `snitch_cluster_wrapper` for Quartus.
S2.1 showed that translating the full cluster through `sv2v` is not a good path
for DE1-SoC: the full target pulls in too much AXI, cluster, assertion, and
tech-cell SystemVerilog.

S3 therefore reduces the scope:

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
Not a replacement for S0/S1 simulation.
Not a board-programmable LED demo yet.
```

At this stage, S3 is a feasibility probe. If the reduced core subset can pass
translation/parsing, the next step is to add simple ROM/RAM/MMIO around it.

## Run

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s3_snitch_core_only_probe
./scripts/run_sv2v_probe.sh
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
```

Command:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s3_snitch_core_only_probe
./scripts/run_sv2v_probe.sh
```

Important meaning:

```text
This proves:
  A real upstream snitch.sv instance can be reduced enough for sv2v/yosys.
  The DE1 path should continue with the core-only shell, not the full cluster.

This does not yet prove:
  Quartus can compile/place/route it.
  The design fits in Cyclone V.
  The core can fetch from ROM/RAM.
  The board LEDs/UART/MMIO are driven by actual Snitch software.
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
S4 candidate:
  add tiny instruction ROM
  add tiny data RAM or fixed MMIO response
  make Snitch execute a minimal instruction sequence
  expose one core-visible event on LEDR
```

The first board-visible goal should stay small:

```text
Snitch fetches instructions -> performs one store/load/event -> LED changes
```
