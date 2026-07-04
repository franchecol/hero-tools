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

## Attempt 6: Shift/Spill Register Common Cells Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/shift_reg.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/shift_reg_gated.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/spill_register_flushable.sv
snitch_cluster/hw/snitch_cluster/src/snitch_cluster.sv
snitch_cluster/hw/snitch_cluster/src/snitch_tcdm_interconnect.sv
snitch_cluster/hw/snitch_cluster/src/snitch_sequencer.sv
snitch_cluster/hw/future/src/dma/axi_dma_data_mover.sv
snitch_cluster/hw/future/src/dma/axi_dma_backend.sv
```

What changed:

```text
shift_reg.sv:
  replaced dtype type parameter with DATA_WIDTH vector ports
  changed the internal shift_reg_gated override from .dtype(...) to .DATA_WIDTH(...)

shift_reg_gated.sv:
  replaced dtype type parameter with DATA_WIDTH vector ports/storage
  wrapped module-level generate-if logic with explicit generate/endgenerate
  replaced inline for-loop genvar with a separately declared genvar

spill_register_flushable.sv:
  replaced T type parameter with DATA_WIDTH vector ports/storage
  wrapped module-level generate-if logic with explicit generate/endgenerate

call sites:
  changed active shift_reg and fifo_v3 type overrides to explicit DATA_WIDTH overrides
```

Important progress:

```text
The previous first errors in shift_reg.sv, shift_reg_gated.sv, and
spill_register_flushable.sv are gone.
```

New first Quartus error:

```text
common_cells/src/stream_fork.sv:83
Error (10170): Verilog HDL syntax error near text: "for"; expecting "endmodule"
```

Other errors in the same run:

```text
common_cells/src/stream_intf.sv: parameter type in simulation/DV helper code
common_cells/src/stream_join_dynamic.sv: implicit module-level generate-for
common_cells/src/stream_mux.sv: parameter type
common_cells/src/stream_throttle.sv: parameter type
common_cells/src/sub_per_hash.sv: implicit module-level generate-for
common_cells/src/read.sv: parameter type
```

Interpretation:

```text
Quartus is now past the shift/spill-register utilities and has advanced into
the stream-helper portion of Common Cells. This is another distinct source
group, not the same failing files.
```

## Attempt 7: Stream Helper Common Cells Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_fork.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_join_dynamic.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_mux.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_throttle.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/sub_per_hash.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/read.sv
snitch_cluster/hw/reqrsp_interface/src/axi_to_reqrsp.sv
```

What changed:

```text
source list:
  removed stream_intf.sv from the Quartus preflight list
  reason: STREAM_DV is only referenced from testbench code, not the synthesis top

stream_fork.sv:
  wrapped module-level generate-for logic with explicit generate/endgenerate
  replaced inline for-loop genvar with a separately declared genvar

stream_join_dynamic.sv:
  wrapped module-level generate-for logic with explicit generate/endgenerate
  replaced inline for-loop genvar with a separately declared genvar

stream_mux.sv:
  replaced DATA_T type parameter with DATA_WIDTH vector ports

stream_throttle.sv:
  removed the credit_t type parameter and used explicit CntWidth vectors

sub_per_hash.sv:
  wrapped nested module-level generate-for logic with explicit generate/endgenerate
  replaced inline for-loop genvars with separately declared genvars

read.sv:
  removed the T type parameter and used explicit Width vector ports

axi_to_reqrsp.sv:
  changed the active stream_mux override from .DATA_T(meta_t) to .DATA_WIDTH($bits(meta_t))
```

Important progress:

```text
The previous first errors in stream_fork.sv, stream_intf.sv,
stream_join_dynamic.sv, stream_mux.sv, stream_throttle.sv, sub_per_hash.sv,
and read.sv are gone.
The preflight source count is now files=311 because the unused stream_intf.sv
interface helper is no longer passed to Quartus.
```

New first Quartus error:

```text
common_cells/src/addr_decode_dync.sv:46
Error (10170): Verilog HDL syntax error near text: "type";
expecting an identifier ("type" is a reserved keyword)
```

Other errors in the same run:

```text
common_cells/src/addr_decode_dync.sv: function type parameter syntax
common_cells/src/boxcar.sv: localparam in parameter list
common_cells/src/cdc_2phase.sv: parameter type
common_cells/src/cdc_4phase.sv: parameter type and implicit generate-if
```

Interpretation:

```text
Quartus is now past the stream helper group. The next group is decoder/helper
math plus CDC primitives. Some of these may be unused in the one-clock DE1-SoC
experiment, but they are still present in the broad frozen file list.
```

## Attempt 8: Address Decoder And CDC Pruning Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/addr_decode_dync.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/addr_decode.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/addr_decode_napot.sv
snitch_cluster/hw/snitch_cluster/src/snitch_cc.sv
```

What changed:

```text
source list:
  removed unused CDC and boxcar helper files from the Quartus preflight list
  reason: no CDC modules are referenced by the active hw/target hierarchy

addr_decode_dync.sv:
  replaced addr_t/rule_t/idx_t type parameters with AddrWidth, RuleIdxWidth, and IdxWidth
  changed ports to explicit packed vectors
  cast the vector address map into a local rule struct for field access

addr_decode.sv:
  replaced addr_t/rule_t/idx_t type parameters with explicit width parameters
  forwarded those widths to addr_decode_dync

addr_decode_napot.sv:
  replaced addr_t/rule_t/idx_t type parameters with explicit width parameters
  converted NAPOT rule fields into the addr_decode_dync start/end field layout locally

snitch_cc.sv:
  changed the active addr_decode_napot override from type parameters to width parameters
```

Important progress:

```text
The previous first addr_decode_dync.sv type-parameter error is gone.
The broad preflight list was reduced from files=311 to files=302.
```

New first Quartus error:

```text
common_cells/src/clk_int_div_static.sv:70
Error (10170): Verilog HDL syntax error near text: "if"; expecting "endmodule"
```

Other errors in the same run:

```text
common_cells/src/multiaddr_decode.sv: parameter type
common_cells/src/cb_filter.sv: implicit module-level generate-for
common_cells/src/clk_mux_glitch_free.sv: localparam in parameter list
common_cells/src/ecc_decode.sv: parameter type
common_cells/src/ecc_encode.sv: parameter type
common_cells/src/lzc.sv: implicit module-level generate-if
```

Interpretation:

```text
The manual fork is now past address-decoder parsing and unused CDC parsing.
The next blocker is another Common Cells utility batch.
```

## Attempt 9: LZC And Utility Pruning Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/lzc.sv
```

What changed:

```text
source list:
  removed unused clk_int_div_static, multiaddr_decode, cb_filter,
  clk_mux_glitch_free, ecc_decode, and ecc_encode helpers from the preflight list

lzc.sv:
  wrapped module-level generate-if and generate-for logic with explicit generate/endgenerate
  replaced inline for-loop genvars with separately declared genvars
```

Important progress:

```text
The previous first clk_int_div_static.sv error is gone by pruning an unused helper.
The active lzc.sv generate-syntax errors are gone.
The broad preflight list was reduced from files=302 to files=296.
```

New first Quartus error:

```text
common_cells/src/spill_register.sv:18
Error (10170): Verilog HDL syntax error near text: "type";
expecting an identifier ("type" is a reserved keyword)
```

Other errors in the same run:

```text
common_cells/src/stream_delay.sv: parameter type and implicit generate-if
common_cells/src/stream_fifo.sv: parameter type
common_cells/src/stream_fork_dynamic.sv: implicit module-level generate-for
common_cells/src/fall_through_register.sv: parameter type
```

Interpretation:

```text
The parser has moved from decoder/utility modules to Common Cells stream/spill
wrapper modules. These wrap lower-level modules that were already partially
ported in earlier attempts.
```

## Attempt 10: Stream/Spill Wrapper Common Cells Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/spill_register.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_fifo.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_fork_dynamic.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/fall_through_register.sv
```

What changed:

```text
source list:
  removed unused stream_delay.sv from the preflight list

spill_register.sv:
  replaced T type parameter with DATA_WIDTH vector ports
  changed the flushable spill-register override to .DATA_WIDTH(...)

stream_fifo.sv:
  removed T type parameter
  used DATA_WIDTH vector ports
  removed stale fifo_v3 .dtype(...) override

stream_fork_dynamic.sv:
  wrapped module-level generate-for logic with explicit generate/endgenerate
  replaced inline for-loop genvar with a separately declared genvar

fall_through_register.sv:
  replaced T type parameter with DATA_WIDTH vector ports
  changed the fifo_v3 override to .DATA_WIDTH(...)
```

Important progress:

```text
The previous first errors in spill_register.sv, stream_delay.sv, stream_fifo.sv,
stream_fork_dynamic.sv, and fall_through_register.sv are gone.
The broad preflight list was reduced from files=296 to files=295.
```

New first Quartus error:

```text
common_cells/src/id_queue.sv:56
Error (10170): Verilog HDL syntax error near text: "type";
expecting an identifier ("type" is a reserved keyword)
```

Other errors in the same run:

```text
common_cells/src/id_queue.sv: parameter type and implicit module-level generate-for
common_cells/src/stream_to_mem.sv: parameter type
```

Interpretation:

```text
The parser has moved to queue/memory-stream Common Cells utilities. The stream
wrapper layer is now syntactically acceptable to Quartus.
```

## Attempt 11: Stream-To-Memory Common Cells Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_to_mem.sv
snitch_cluster/hw/tcdm_interface/src/reqrsp_to_tcdm.sv
snitch_cluster/hw/snitch_cluster/src/snitch_cc.sv
```

What changed:

```text
source list:
  removed unused id_queue.sv from the preflight list

stream_to_mem.sv:
  replaced mem_req_t and mem_resp_t type parameters with MemReqWidth and MemRespWidth
  changed request/response payload ports to explicit packed vectors
  wrapped module-level generate-if logic with explicit generate/endgenerate
  changed the internal stream_fifo override to .DATA_WIDTH(...)

reqrsp_to_tcdm.sv and snitch_cc.sv:
  changed active stream_to_mem overrides from type parameters to width parameters
```

Important progress:

```text
The previous first id_queue.sv parser errors are gone by pruning an unused helper.
The active stream_to_mem.sv type/generate errors are gone.
The broad preflight list was reduced from files=295 to files=294.
```

New first Quartus error:

```text
common_cells/src/stream_arbiter_flushable.sv:17
Error (10170): Verilog HDL syntax error near text: "type";
expecting an identifier ("type" is a reserved keyword)
```

Other errors in the same run:

```text
common_cells/src/stream_arbiter_flushable.sv: parameter type and implicit generate-if
common_cells/src/stream_fifo_optimal_wrap.sv: parameter type and implicit generate-if
common_cells/src/stream_register.sv: parameter type
common_cells/src/stream_xbar.sv: parameter type
```

Interpretation:

```text
The parser has moved into stream arbitration and crossbar helper modules.
These are on the active TCDM interconnect path, so this likely requires real
porting rather than broad pruning.
```

## Attempt 12: Stream Arbiter/Xbar Common Cells Batch

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
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_arbiter_flushable.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_arbiter.sv
snitch_cluster/.bender/git/checkouts/common_cells-*/src/stream_xbar.sv
snitch_cluster/hw/snitch_cluster/src/snitch_tcdm_interconnect.sv
```

What changed:

```text
source list:
  removed unused stream_fifo_optimal_wrap.sv and stream_register.sv from the preflight list

stream_arbiter_flushable.sv:
  replaced DATA_T type parameter with DATA_WIDTH vector ports
  changed rr_arb_tree overrides to .DataWidth(...)
  wrapped the ARBITER generate-if tree with explicit generate/endgenerate
  wrapped the invalid-parameter $fatal in an initial block

stream_arbiter.sv:
  replaced DATA_T type parameter with DATA_WIDTH vector ports
  changed the flushable arbiter override to .DATA_WIDTH(...)

stream_xbar.sv:
  removed payload/index/select type parameters from the port list
  used explicit DataWidth, SelWidth, IdxWidth, and SpillDataWidth vector ports
  changed rr_arb_tree and spill_register overrides to width parameters
  wrapped module-level generate loops with explicit generate/endgenerate
  skipped assertion generate loops in S2_3_QUARTUS mode

snitch_tcdm_interconnect.sv:
  changed the active stream_xbar override from .payload_t(...) to .DataWidth($bits(...))
```

Important progress:

```text
The previous first stream_arbiter_flushable.sv parser errors are gone.
The stream_arbiter.sv and stream_xbar.sv type-parameter parser errors are gone.
The broad preflight list was reduced from files=294 to files=292.
```

New first Quartus error:

```text
common_cells/src/mem_to_banks_detailed.sv:35
Error (10170): Verilog HDL syntax error near text: "type";
expecting an identifier ("type" is a reserved keyword)
```

Other errors in the same run:

```text
common_cells/src/mem_to_banks_detailed.sv: parameter type and implicit generate syntax
common_cells/src/stream_omega_net.sv: parameter type
```

Interpretation:

```text
The parser has moved beyond stream xbar/arbiter and into remaining active
bank-routing and omega-network helpers.
```

## Attempt 13: Bank-Routing/Omega Pruning Batch

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
```

What changed:

```text
source list:
  removed mem_to_banks_detailed.sv and mem_to_banks.sv
  removed stream_omega_net.sv
```

Why this is safe for this experiment:

```text
The generated Snitch wrapper sets:
  .Topology (snitch_pkg::LogarithmicInterconnect)

That selects the stream_xbar branch in snitch_tcdm_interconnect.sv. The
stream_omega_net branch is inactive for this one-core DE1 preflight.

mem_to_banks_detailed.sv and mem_to_banks.sv have no active users in the
current hw/target hierarchy.
```

Important progress:

```text
The previous first mem_to_banks_detailed.sv parser errors are gone by pruning
inactive helpers.
The stream_omega_net.sv type-parameter parser errors are gone by pruning the
inactive topology implementation.
The broad preflight list was reduced from files=292 to files=289.
```

New first Quartus error:

```text
common_cells/src/deprecated/clk_div.sv:44
Error (10170): Verilog HDL syntax error near text: "if"; expecting "endmodule"
```

Other errors in the same run:

```text
common_cells/src/deprecated/find_first_one.sv: implicit generate-for
common_cells/src/deprecated/prioarbiter.sv: implicit generate-for/if
common_cells/src/deprecated/fifo_v2.sv: parameter type and implicit generate-if
```

Interpretation:

```text
Quartus is now reaching deprecated Common Cells helpers. These are likely
included by the broad original file list rather than required by the reduced
DE1 Snitch-cluster top.
```
