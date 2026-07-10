# Q2.2 Error Log

This file records the direct Quartus patch-overlay attempts.

## Baseline: Original Q2, No Patch

Command:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/q2_snitch_quartus_wrapper
./scripts/quartus_preflight.sh
```

Result:

```text
FAIL
quartus_map exit code: 3
no .sof produced
```

First meaningful Quartus error:

```text
tc_sram.sv:69
Error (10170): near text: "type"; expecting an identifier
```

Cause:

```text
The original tech_cells_generic SRAM wrapper uses SystemVerilog type parameters:

parameter type addr_t = logic [AddrWidth-1:0]
parameter type data_t = logic [DataWidth-1:0]
parameter type be_t   = logic [BeWidth-1:0]
```

Interpretation:

```text
Quartus Lite rejects this construct in the original generated Snitch cluster
dependency tree.
```

## Attempt 1: Patch SRAM Type Parameters

Command:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/q2_2_snitch_patch_overlay
./scripts/quartus_preflight.sh
```

Patch overlay:

```text
generated/patches/tech_cells_generic/src/rtl/tc_sram.sv
generated/patches/tech_cells_generic/src/rtl/tc_sram_impl.sv
generated/patches/snitch_cluster/src/snitch_cluster.sv
generated/patches/snitch_icache/src/snitch_icache_lookup.sv
```

What changed:

```text
tc_sram.sv:
  removed addr_t/data_t/be_t type parameters
  replaced them with explicit logic vector ports/internal declarations

tc_sram_impl.sv:
  removed impl_in_t/impl_out_t/addr_t/data_t/be_t type parameters
  replaced implementation-control ports with 1-bit logic

snitch_cluster.sv and snitch_icache_lookup.sv:
  removed .impl_in_t(...) SRAM parameter overrides
  tied unused .impl_i ports to 1'b0
```

Result:

```text
FAIL
quartus_map exit code: 3
no .sof produced
```

Important progress:

```text
The original tc_sram.sv/tc_sram_impl.sv "parameter type" errors are gone.
```

New first Quartus error:

```text
generated/patches/tech_cells_generic/src/rtl/tc_sram.sv:114
Error (10170): near text: "if"; expecting "endmodule"
```

New compatibility class:

```text
Quartus now rejects implicit module-level generate syntax in tc_sram.sv.
The same run also reports similar generate-style issues in:

tech_cells_generic/src/deprecated/generic_memory.sv
common_cells/src/cc_onehot.sv
common_cells/src/clk_int_div.sv
```

Interpretation:

```text
The first issue was solved, but the original full generated cluster still has
more Quartus syntax-compatibility blockers. Continuing this path means adding
more local source rewrites, not just one SRAM type-parameter patch.
```

