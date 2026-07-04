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

Line-level comparison against the original Occamy/Bender checkout:

```text
patches/attempt1_sram_type_parameter_port.patch
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

## Attempt 2: Explicit Generate Syntax Patch

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
snitch_cluster/.bender/git/checkouts/tech_cells_generic-*/src/deprecated/generic_memory.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/cc_onehot.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/clk_int_div.sv
```

What changed:

```text
tc_sram.sv:
  wrapped module-level generate-if regions with explicit generate/endgenerate
  replaced inline genvar declaration with a separately declared genvar

generic_memory.sv:
  named previously unnamed generate begin blocks

cc_onehot.sv:
  wrapped module-level generate-if/for logic with explicit generate/endgenerate
  replaced inline genvar declarations with separately declared genvars

clk_int_div.sv:
  wrapped the elaboration parameter check with explicit generate/endgenerate
  moved the Quartus-hostile bare $error into an initial block
```

Important progress:

```text
The previous tc_sram.sv, generic_memory.sv, cc_onehot.sv, and clk_int_div.sv
generate-syntax parser errors are gone.
```

New first Quartus error:

```text
common_cells/include/common_cells/registers.svh:47
Error (10115): Verilog HDL Macro Definition syntax error
illegal character in macro parameter near "= `REG_DFLT_CLK, __arst_n = `REG_DFLT_RST)"
```

New compatibility class:

```text
Quartus rejects default values in Verilog macro parameter lists.
The same run reports the same macro-default syntax issue in:

common_cells/include/common_cells/registers.svh
common_cells/include/common_cells/assertions.svh
```

Interpretation:

```text
The manual fork is now past the first generate-style incompatibilities.
The next class is preprocessor macro syntax rather than module generate syntax.
```

## Attempt 3: Quartus-Safe Macro Mode

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
source_list/snitch_cluster.flist-plus.in
snitch_cluster/.bender/git/checkouts/common_cells-*/include/common_cells/registers.svh
snitch_cluster/.bender/git/checkouts/common_cells-*/include/common_cells/assertions.svh
selected source files using `FF, `FFL, and assertion macros
```

What changed:

```text
source list:
  added S2_3_QUARTUS define

registers.svh:
  removed default macro arguments from `FF and `FFL
  explicit clock/reset arguments are now required

assertions.svh:
  added S2_3_QUARTUS mode with fixed-arity no-op assertion macros
  this avoids parsing simulation/formal assertion syntax during Quartus synthesis

call sites:
  added clk_i/rst_ni to implicit `FF and `FFL calls
  dropped optional clock/reset/description arguments from no-op assertion calls
```

Important progress:

```text
The previous registers.svh/assertions.svh default macro argument errors are gone.
The generated source list now reports defines=5, including S2_3_QUARTUS.
```

New first Quartus error:

```text
common_cells/src/credit_counter.sv:17
Error (10170): Verilog HDL syntax error near text: "type";
expecting an identifier ("type" is a reserved keyword)
```

Other errors in the same run:

```text
common_cells/src/delta_counter.sv: implicit module-level generate-if
common_cells/src/fifo_v3.sv: parameter type and implicit generate-if
common_cells/src/gray_to_binary.sv: implicit module-level generate-for
common_cells/src/heaviside.sv: type-like localparam syntax rejected
common_cells/src/isochronous_spill_register.sv: parameter type and implicit generate-if
```

Interpretation:

```text
The manual fork is now past macro-preprocessor incompatibilities.
The next class is common_cells module syntax: more parameter type usage plus
more implicit generate blocks.
```

## Attempt 4: First Common Cells Type/Generate Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/credit_counter.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/delta_counter.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/fifo_v3.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/gray_to_binary.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/heaviside.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/isochronous_spill_register.sv
```

What changed:

```text
credit_counter.sv:
  removed the credit_cnt_t type parameter
  used explicit logic vector widths for the counter ports/registers

delta_counter.sv:
  wrapped module-level generate-if with explicit generate/endgenerate

fifo_v3.sv:
  replaced dtype type parameter with DATA_WIDTH vector ports/storage
  wrapped module-level generate-if with explicit generate/endgenerate

gray_to_binary.sv:
  replaced inline genvar generate-for with explicit genvar plus generate/endgenerate

heaviside.sv:
  removed localparam type parameters
  changed the derived parameter list syntax to Quartus-accepted parameter syntax

isochronous_spill_register.sv:
  replaced T type parameter with DATA_WIDTH vector ports/storage
  wrapped module-level generate-if with explicit generate/endgenerate
```

Important progress:

```text
The previous first errors in credit_counter.sv, delta_counter.sv, fifo_v3.sv,
gray_to_binary.sv, heaviside.sv, and isochronous_spill_register.sv are gone.
```

New first Quartus error:

```text
common_cells/src/lfsr.sv:254
Error (10170): Verilog HDL syntax error near text: "if"; expecting "endmodule"
```

Other errors in the same run:

```text
common_cells/src/lossy_valid_to_stream.sv: parameter type
common_cells/src/onehot_to_bin.sv: implicit module-level generate-for
common_cells/src/passthrough_stream_fifo.sv: parameter type
common_cells/src/popcount.sv: localparam in parameter list
common_cells/src/ring_buffer.sv: parameter type
common_cells/src/rr_arb_tree.sv: parameter type
```

Interpretation:

```text
Quartus is now deeper into common_cells. The remaining blockers are the same
families repeated across more reusable utility modules.
```

## Attempt 5: Second Common Cells Type/Generate Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/lfsr.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/lossy_valid_to_stream.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/onehot_to_bin.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/passthrough_stream_fifo.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/popcount.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/ring_buffer.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/rr_arb_tree.sv
snitch_cluster/hw/tcdm_interface/src/tcdm_mux.sv
snitch_cluster/hw/reqrsp_interface/src/reqrsp_mux.sv
selected source files with no-op assertion macro call sites
```

What changed:

```text
lfsr.sv:
  wrapped module-level generate-if logic with explicit generate/endgenerate

lossy_valid_to_stream.sv:
  replaced T type parameter with DATA_WIDTH vector ports/storage

onehot_to_bin.sv:
  replaced inline generate-for declarations with explicit genvars and generate/endgenerate

passthrough_stream_fifo.sv:
  replaced type_t type parameter with DATA_WIDTH vector ports/storage

popcount.sv:
  changed derived PopcountWidth to Quartus-accepted parameter syntax
  wrapped the elaboration parameter check with explicit generate/endgenerate

ring_buffer.sv:
  replaced data_t type parameter with DATA_WIDTH vector ports/storage
  removed trailing semicolons after disabled assertion macros

rr_arb_tree.sv:
  replaced DataType and idx_t type parameters with DATA_WIDTH and IdxWidth vectors
  wrapped module-level generate logic with explicit generate/endgenerate

tcdm_mux.sv and reqrsp_mux.sv:
  changed rr_arb_tree overrides from .DataType(...) to .DataWidth($bits(...))
```

Important progress:

```text
The previous first errors in lfsr.sv, lossy_valid_to_stream.sv,
onehot_to_bin.sv, passthrough_stream_fifo.sv, popcount.sv, ring_buffer.sv, and
rr_arb_tree.sv are gone.
```

New first Quartus error:

```text
common_cells/src/shift_reg.sv:17
Error (10170): Verilog HDL syntax error near text: "type";
expecting an identifier ("type" is a reserved keyword)
```

Other errors in the same run:

```text
common_cells/src/shift_reg_gated.sv: parameter type and implicit generate syntax
common_cells/src/spill_register_flushable.sv: parameter type and implicit generate syntax
```

Interpretation:

```text
The parser is still in Common Cells, but it has advanced to the shift-register
and spill-register utility group. This confirms the previous batch was not just
moving line numbers inside the same files; it cleared a full module group.
```
