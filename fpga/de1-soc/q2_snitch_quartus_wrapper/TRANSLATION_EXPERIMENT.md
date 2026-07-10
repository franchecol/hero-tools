# Q2.1 Translation Experiment Result

This note records the experiment that tried to make the Q2 Snitch cluster
Quartus-compatible by translating the generated SystemVerilog before Quartus
sees it.

## Goal

Q2 proved that the Quartus project packaging path works:

```text
Bender file list -> generated QSF -> Quartus project
```

But Quartus Lite 25.1 failed during analysis/elaboration on advanced
SystemVerilog syntax in the unmodified Snitch dependency tree. The first real
Quartus error was:

```text
tc_sram.sv(69): parameter type addr_t = logic [AddrWidth-1:0]
```

The experiment asked:

```text
Can we translate the full generated Snitch cluster RTL into simpler Verilog or
Quartus-friendlier SystemVerilog and then continue with Quartus?
```

## Tools Installed

The tools were installed rootlessly under the user home directory, without
modifying system packages:

```text
sv2v:
  wrapper: ~/.local/bin/sv2v
  version: sv2v 0.0.13

yosys:
  wrapper: ~/.local/bin/yosys
  version: Yosys 0.66

local install prefix:
  ~/.local/opt/snitch-sv-tools

local package cache:
  ~/.cache/snitch-sv-tools
```

Both tools passed small smoke tests:

```text
sv2v:
  Converted a tiny module using parameter type.

yosys:
  Parsed a tiny Verilog module.
```

## Experiment Inputs

The input file list came from the Q2 Bender export:

```text
generated/snitch_cluster.flist-plus
```

That list contains the full `snitch_cluster` target:

```text
include directories: 9
defines:             4
RTL files:           312
```

This is important: the experiment was not only translating `snitch.sv`; it was
translating the whole generated cluster dependency graph, including AXI,
register interface, tech cells, future DMA blocks, the cluster wrapper, and
Snitch internals.

## Attempts

### Attempt 1: Translate The Full Bender File List

Command shape:

```text
sv2v + Bender include dirs + Bender defines + all 312 files + Q2 wrapper
```

Result:

```text
FAIL
```

First blocker:

```text
tech_cells_generic/src/deprecated/pad_functional.sv:41
Parse error: missing expected `endmodule`
```

Reason:

```text
The full target includes deprecated pad/power-cell primitive models that are
not useful for the DE1-SoC wrapper and are not clean inputs for sv2v.
```

### Attempt 2: Exclude Obvious Unused Deprecated Pad/Power Files

Excluded:

```text
deprecated/pad_functional.sv
deprecated/cluster_pwr_cells.sv
deprecated/pulp_pwr_cells.sv
```

Result:

```text
FAIL
```

Next blocker:

```text
axi_pkg.sv:210
Parse error: missing expected `endfunction`
```

The failing construct was a local typedef inside a function:

```systemverilog
typedef shortint unsigned SU;
```

Reason:

```text
This is not a Quartus problem anymore. It is an sv2v parser limitation on a
legal SystemVerilog construct used by the AXI dependency package.
```

### Attempt 3: Temporary Generated Patch For axi_pkg.sv

A temporary generated copy of `axi_pkg.sv` removed the local typedef and
replaced the local alias cast with a direct `shortint` cast.

Result:

```text
FAIL
```

Next blocker:

```text
axi_burst_splitter_gran.sv:400
Parse error: missing expected `endmodule`
```

The failing code was assertion-only code:

```systemverilog
default disable iff (!rst_ni);
```

Reason:

```text
The full dependency tree contains assertion/property syntax that is meant for
simulation/formal tools, not for this translation path.
```

### Attempt 4: Define VERILATOR To Remove Assertion Blocks

Added:

```text
-DVERILATOR
```

This moved the experiment past the assertion block.

Result:

```text
FAIL
```

Next blocker:

```text
snitch_cc.sv:658
Parse error: missing expected `end`
```

The failing construct was inside real Snitch cluster code:

```systemverilog
always_comb begin
  import riscv_instr::*;
  automatic logic [11:0] addr;
```

At this point the experiment had already required:

```text
excluded files
temporary generated source patching
preprocessor defines to skip assertions
```

and still failed on Snitch cluster RTL.

## Why Continuing This Path Is Not Recommended

The experiment shows that full-cluster translation is not blocked by one small
syntax issue. It is a chain of compatibility problems across several layers:

```text
tech-cell primitive models
AXI dependency package syntax
assertion/property syntax
Snitch cluster procedural imports
duplicate AXI module definitions in the full target file list
```

Continuing would mean building a growing custom translation pipeline:

```text
filter some Bender files
patch selected dependency files
define tool-specific macros
rerun sv2v
debug next parser failure
feed translated output to Quartus
debug next Quartus failure
repeat
```

That is a bad use of time for this DE1-SoC educational path because:

```text
1. It would be fragile.
   The pipeline would depend on local generated patches against third-party
   dependencies.

2. It would be hard to trust.
   After enough source rewriting, passing Quartus would no longer mean we are
   testing the same RTL structure that Q0/Q1 simulated.

3. It still would not prove FPGA fit.
   Even if sv2v completed, Quartus could still fail later on memory inference,
   unsupported constructs, resource usage, timing, or placement.

4. The full cluster is larger than our immediate learning goal.
   The DE1-SoC board is useful for proving a small real-core accelerator path,
   not for forcing the complete ASIC-oriented cluster fabric through Quartus.

5. The next failures are not likely to be educationally valuable.
   They would mostly be tool-compatibility patching rather than learning how to
   integrate a Snitch-style accelerator.
```

## Decision

Do not continue trying to translate the full `snitch_cluster_wrapper` for
Quartus Lite.

Keep this result as useful evidence:

```text
Q2:
  Quartus project packaging works.

Q2.1:
  Full-cluster sv2v translation is high-friction and not recommended.
```

## Recommended Next Step

Move to a reduced core-only path:

```text
SL3:
  Instantiate the real snitch core directly.
  Avoid the generated full cluster wrapper.
  Avoid the full AXI/future-DMA/cluster dependency tree.
  Provide tiny local shims only for the package types needed by the core.
  Connect:
    instruction input
    simple data request/response type
    simple accelerator response type
    LEDs/debug signals
```

The goal of SL3 is not yet to run a complete program on the DE1-SoC board. The
first goal is narrower:

```text
Can a much smaller real-Snitch-core subset be accepted by the translation and
FPGA tooling path?
```

If SL3 succeeds, then the next step is to add real ROM/RAM/MMIO behavior around
that core.

## Follow-Up Status

SL3 was created after this decision:

```text
fpga/de1-soc/sl3_snitch_core_only_probe/
```

SL3 validates the pivot:

```text
sv2v:
  PASS for a reduced real snitch.sv instance.

yosys:
  PASS for parse, elaboration, process lowering, and check.

Quartus:
  PASS for analysis/elaboration and full compile of the translated SL3 shell.
```

This does not make the full-cluster path good. It shows the opposite: reducing
the target to the real core plus a tiny local shell is the practical path for
DE1-SoC work.
