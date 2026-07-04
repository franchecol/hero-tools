# S2.2 Original Snitch Patch Overlay Experiment

This experiment continues from S2 without using `sv2v` or any other
translation tool.

The goal is deliberately narrow:

```text
Start from the original generated Snitch cluster.
Patch only the first Quartus blocker.
Run Quartus analysis/elaboration again.
Record the next blocker.
```

## Why This Exists

S2 proved that the unmodified generated Snitch cluster can be exported as a
Quartus project, but Quartus Lite 25.1 fails during analysis/elaboration before
producing a bitstream.

The first direct failure was:

```text
tc_sram.sv:69
Error (10170): near text: "type"; expecting an identifier
```

The failing construct is a SystemVerilog type parameter:

```systemverilog
parameter type addr_t = logic [AddrWidth-1:0]
```

Quartus Lite does not accept this construct in the original tech-cell SRAM
files used by the full generated Snitch cluster.

## What This Experiment Patches

The patch is intentionally an overlay:

```text
original upstream files remain untouched
patched copies are generated under generated/patches/
the generated QSF is rewritten to point at the patched copies
```

The first patch removes `parameter type` usage from:

```text
tech_cells_generic/src/rtl/tc_sram.sv
tech_cells_generic/src/rtl/tc_sram_impl.sv
```

Because `tc_sram_impl` call sites pass a type parameter, patched copies of these
call-site files are also generated:

```text
hw/snitch_cluster/src/snitch_cluster.sv
hw/snitch_icache/src/snitch_icache_lookup.sv
```

Those call-site patches remove `.impl_in_t(...)` and tie the unused
implementation-control input to `1'b0`.

## Run

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s2_2_snitch_patch_overlay
./scripts/quartus_preflight.sh
```

## Expected Result

This experiment is not expected to produce a usable `.sof`.

Success for this stage means:

```text
the original tc_sram/tc_sram_impl "parameter type" error is gone
Quartus reaches the next blocker
the new blocker is recorded here
```

## Current Result

Attempt 1 was run locally with Quartus Prime Lite 25.1std.0.

Result:

```text
FAIL
no .sof produced
```

Important progress:

```text
The original tc_sram.sv/tc_sram_impl.sv "parameter type" errors are gone.
```

New first blocker:

```text
generated/patches/tech_cells_generic/src/rtl/tc_sram.sv:114
Error (10170): near text: "if"; expecting "endmodule"
```

Meaning:

```text
Quartus now reaches the next syntax-compatibility class: implicit module-level
generate syntax. The same run also reports similar generate-block issues in
generic_memory.sv, cc_onehot.sv, and clk_int_div.sv.
```

For details, read:

```text
ERROR_LOG.md
```
