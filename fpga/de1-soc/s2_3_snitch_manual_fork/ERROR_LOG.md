# S2.3 Error Log

This log records the manual Snitch fork porting experiment.

## Baseline From S2

The unmodified generated Snitch cluster failed in Quartus Lite 25.1 at:

```text
tc_sram.sv:69
Error (10170): near text: "type"; expecting an identifier
```

Cause:

```text
tech_cells_generic/src/rtl/tc_sram.sv uses SystemVerilog type parameters.
```

## Attempt 1: Manual SRAM Type-Parameter Patch

Status:

```text
FAIL
quartus_map exit code: 3
no .sof produced
```

Command:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s2_3_snitch_manual_fork
./scripts/quartus_preflight.sh
```

Manual source edits:

```text
snitch_cluster/.bender/git/checkouts/tech_cells_generic-*/src/rtl/tc_sram.sv
snitch_cluster/.bender/git/checkouts/tech_cells_generic-*/src/rtl/tc_sram_impl.sv
snitch_cluster/hw/snitch_cluster/src/snitch_cluster.sv
snitch_cluster/hw/snitch_icache/src/snitch_icache_lookup.sv
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

Important progress:

```text
The original tc_sram.sv/tc_sram_impl.sv "parameter type" errors are gone.
```

New first Quartus error:

```text
snitch_cluster/.bender/git/checkouts/tech_cells_generic-*/src/rtl/tc_sram.sv:114
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
The manual fork now proves the same result as S2.2 without patch-generation
scripts: the first problem is fixable, but the full generated Snitch cluster
still has additional Quartus syntax-compatibility blockers.
```
