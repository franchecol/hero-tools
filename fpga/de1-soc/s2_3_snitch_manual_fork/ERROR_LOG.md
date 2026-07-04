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

## Attempt 14: Deprecated Common Cells Pruning Batch

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
  removed all common_cells/src/deprecated/*.sv entries from the preflight list
```

Why this is safe for this experiment:

```text
Searching the active hw/target hierarchy found no real deprecated Common Cells
module instantiations. The clk_div matches were local signal names in
snitch_clkdiv2.sv, not instances of deprecated/clk_div.sv.
```

Important progress:

```text
The previous deprecated clk_div.sv, find_first_one.sv, prioarbiter.sv, and
fifo_v2.sv parser errors are gone by pruning inactive legacy helpers.
The broad preflight list was reduced from files=289 to files=277.
```

New first Quartus error:

```text
apb/src/apb_err_slv.sv:26
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
apb_regs.sv: parameter type and implicit generate-for
apb_cdc.sv: parameter type
apb_demux.sv: parameter type and implicit generate-if
```

Interpretation:

```text
Common Cells source-list pruning/porting has reached the APB dependency
boundary. The next decision is whether APB files are active in this reduced
DE1 Snitch-cluster preflight or only included by the broad original file list.
```

## Attempt 15: APB Dependency Pruning Batch

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
  removed the apb_pkg.sv/apb_intf.sv/apb_*.sv dependency block
```

Why this is safe for this experiment:

```text
The active snitch_cluster/hw and snitch_cluster/target trees have no APB
module or package references in this one-core DE1 preflight. The APB files
were only present because the original dependency file list is broad.
```

Important progress:

```text
The previous apb_err_slv.sv, apb_regs.sv, apb_cdc.sv, and apb_demux.sv parser
errors are gone by pruning an unused dependency block.
The broad preflight list was reduced from files=277 to files=271.
```

New first Quartus error:

```text
axi/src/axi_demux_id_counters.sv:23
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_atop_filter.sv: parameter type
axi_burst_splitter_gran.sv: parameter type and implicit generate syntax
many later axi/*.sv files also still use parser features unsupported by this
Quartus flow
```

Interpretation:

```text
The parser has moved from APB into the broad AXI dependency set. The next step
is to separate AXI files that are genuinely required by the generated one-core
cluster from AXI files that only belong to unused full-system infrastructure.
```

## Attempt 16: Unused AXI Helper Pruning Batch

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
  kept the active AXI package, cut, xbar, demux, mux, burst-splitter, memory,
  and error-slave path

  removed unused AXI interface/demo/CDC/AXI-Lite/converter/helper files that
  were not reachable from snitch_cluster_wrapper in this one-core graph
```

Why this is safe for this experiment:

```text
The active cluster still keeps the AXI modules needed by snitch_cluster.sv:
axi_cut, axi_xbar, axi_xbar_unmuxed, axi_demux, axi_demux_simple,
axi_demux_id_counters, axi_mux, axi_atop_filter, axi_burst_splitter,
axi_burst_splitter_gran, axi_err_slv, axi_multicut, axi_to_detailed_mem,
axi_to_mem, axi_to_mem_interleaved, axi_to_axi_lite, and axi_zero_mem.
```

Important progress:

```text
The broad preflight list was reduced from files=271 to files=230.
The first blocker intentionally did not move, because axi_demux_id_counters.sv
is part of the active AXI xbar path and now needs real syntax porting.
```

Current first Quartus error:

```text
axi/src/axi_demux_id_counters.sv:23
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_atop_filter.sv: parameter type
axi_burst_splitter_gran.sv: parameter type and implicit generate syntax
```

Interpretation:

```text
The AXI dependency boundary is now clearer: most inactive AXI noise is removed,
and remaining early errors are in modules used by the one-core cluster's AXI
crossbar/memory path.
```

## Attempt 17: AXI Demux ID Counter Port

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_demux_id_counters.sv
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_demux_simple.sv
```

What changed:

```text
axi_demux_id_counters.sv:
  replaced mst_port_select_t type parameter with SelectWidth
  changed select ports/storage to explicit packed vectors
  wrapped the counter generate-for loop with explicit generate/endgenerate
  moved the genvar declaration outside the for-loop for Quartus compatibility

axi_demux_simple.sv:
  updated the AW and AR id-counter instances to pass .SelectWidth(SelectWidth)
```

Important progress:

```text
The previous first axi_demux_id_counters.sv type-parameter and generate-loop
parser errors are gone.
```

New first Quartus error:

```text
axi/src/axi_atop_filter.sv:43
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_burst_splitter_gran.sv: parameter type and implicit generate syntax
axi_cut.sv: parameter type
```

Interpretation:

```text
Quartus is now past the AXI demux id counter and into the next active AXI xbar
helper. The remaining AXI work is real porting, not broad dependency cleanup.
```

## Attempt 18: AXI ATOP Filter Port

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_atop_filter.sv
```

What changed:

```text
axi_atop_filter.sv:
  replaced axi_req_t/axi_resp_t type parameters with explicit AXI width parameters
  changed public AXI ports to packed vectors
  recreated the AXI request/response structs internally for field access
  cast vector boundary ports to/from those internal structs
  replaced the inactive stream_register type-parameter instance with spill_register
  skipped the unused AXI interface wrapper in S2_3_QUARTUS mode
```

Important progress:

```text
The previous first axi_atop_filter.sv type-parameter parser error is gone.
Quartus now reaches the next active AXI helper.
```

New first Quartus error:

```text
axi/src/axi_burst_splitter_gran.sv:38
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_burst_splitter_gran.sv: parameter type and implicit generate syntax
axi_cut.sv: parameter type
axi_demux_simple.sv: parameter type
```

Interpretation:

```text
The AXI parser frontier moved through the ATOP filter. Later elaboration may
still require call-site width parameters for axi_atop_filter, but the immediate
parser blocker in that file is gone.
```

## Attempt 19: AXI Burst Splitter S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_burst_splitter_gran.sv
```

What changed:

```text
axi_burst_splitter_gran.sv:
  added an S2_3_QUARTUS-only pass-through implementation
  skipped the original granular burst splitter and helper modules in this mode
```

Important limitation:

```text
This is not a full semantic port of the burst splitter. It assumes the S2.3
bring-up software issues simple single-beat, non-wrapping transfers on this
path. Bursts are not split in the Quartus shim.
```

Important progress:

```text
The previous first axi_burst_splitter_gran.sv type-parameter and helper-module
parser errors are bypassed.
Quartus now reaches axi_cut.sv.
```

New first Quartus error:

```text
axi/src/axi_cut.sv:29
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_demux_simple.sv: parameter type and implicit generate syntax
```

Interpretation:

```text
The AXI parser frontier moved to a simpler active helper, axi_cut.sv. The
burst-splitting behavior remains a documented S2.3 simplification rather than
a complete Quartus port.
```

## Attempt 20: AXI Cut S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_cut.sv
```

What changed:

```text
axi_cut.sv:
  added an S2_3_QUARTUS-only pass-through implementation
  skipped the original AXI cut and interface wrappers in this mode
```

Important limitation:

```text
This is not a full semantic port of the cut/register-slice logic. It does not
insert register cuts. It only forwards request and response vectors directly,
which matches the current S2.3 one-core bring-up need but is not a reusable
replacement for the original AXI cut.
```

Important progress:

```text
The previous axi_cut.sv type-parameter and interface-wrapper parser errors are
bypassed.
Quartus now reaches axi_demux_simple.sv.
```

New first Quartus error:

```text
axi/src/axi_demux_simple.sv:46
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_demux_simple.sv: parameter type and implicit generate syntax
axi_id_prepend.sv: parameter type
```

Interpretation:

```text
The parser frontier moved past axi_cut.sv. The next blocker is the active AXI
demux, which still uses type parameters at its module boundary.
```

## Attempt 21: AXI Demux Simple S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_demux_simple.sv
```

What changed:

```text
axi_demux_simple.sv:
  added an S2_3_QUARTUS-only vector-boundary demux shim
  skipped the original type-parameterized AXI demux implementation in this mode
```

Important limitation:

```text
This is not a full semantic port of the original AXI demux. The shim routes the
whole request vector to selected master ports and returns one selected response
vector. It does not reproduce the original AW/W/B/R channel-specific locking,
ID accounting, or response arbitration.
```

Important progress:

```text
The previous axi_demux_simple.sv type-parameter and generate-parser errors are
bypassed.
Quartus now reaches axi_id_prepend.sv.
```

New first Quartus error:

```text
axi/src/axi_id_prepend.sv:22
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_mux.sv: parameter type and implicit generate syntax
```

Interpretation:

```text
The AXI parser frontier moved through axi_demux_simple.sv. This is useful for
mapping the remaining Quartus-incompatible AXI helpers, but the demux shim is
only an S2.3 bring-up simplification.
```

## Attempt 22: AXI ID Prepend S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_id_prepend.sv
```

What changed:

```text
axi_id_prepend.sv:
  added an S2_3_QUARTUS-only channel-vector pass-through implementation
  skipped the original type-parameterized ID prepend/strip implementation
```

Important limitation:

```text
This is not a full semantic port of the original ID converter. It does not
prepend or strip AXI ID bits; it only passes channel vectors and valid/ready
signals through.
```

Important progress:

```text
The previous axi_id_prepend.sv type-parameter parser errors are bypassed.
Quartus now reaches axi_mux.sv.
```

New first Quartus error:

```text
axi/src/axi_mux.sv:31
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_mux.sv: parameter type, implicit generate syntax, and interface wrapper
axi_to_detailed_mem.sv: parameter type and struct literal syntax
```

Interpretation:

```text
The AXI parser frontier moved through axi_id_prepend.sv. The next blocker is
the active AXI mux helper.
```

## Attempt 23: AXI Mux S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_mux.sv
```

What changed:

```text
axi_mux.sv:
  added an S2_3_QUARTUS-only vector-boundary mux shim
  skipped the original type-parameterized AXI mux and interface wrapper
```

Important limitation:

```text
This is not a full semantic port of the original AXI mux. The shim forwards
slave port 0 to the master and returns the master response to slave port 0. It
does not arbitrate multiple slave ports or preserve ID-extension routing.
```

Important progress:

```text
The previous axi_mux.sv type-parameter, implicit-generate, and wrapper parser
errors are bypassed.
Quartus now reaches axi_to_detailed_mem.sv.
```

New first Quartus error:

```text
axi/src/axi_to_detailed_mem.sv:21
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_to_detailed_mem.sv: parameter type, localparam parser fallout, struct
literals, and implicit generate syntax
```

Interpretation:

```text
The AXI parser frontier moved through axi_mux.sv. This keeps exposing the next
unsupported AXI helper, but the mux behavior is currently only suitable for
parser exploration.
```

## Attempt 24: AXI Detailed Memory S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_to_detailed_mem.sv
```

What changed:

```text
axi_to_detailed_mem.sv:
  added an S2_3_QUARTUS-only vector-boundary memory bridge stub
  skipped the original detailed memory bridge, interface wrapper, and bank
  splitter helper in this mode
```

Important limitation:

```text
This is not a full semantic port of the AXI-to-memory bridge. The stub drives
no memory requests, returns zero AXI response bits, and only exists to map the
remaining Quartus parser blockers.
```

Important progress:

```text
The previous axi_to_detailed_mem.sv type-parameter, helper-module, and wrapper
parser errors are bypassed.
Quartus now reaches axi_burst_splitter.sv.
```

New first Quartus error:

```text
axi/src/axi_burst_splitter.sv:39
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_demux.sv: parameter type and interface wrapper
axi_err_slv.sv: parameter type and generate syntax
axi_multicut.sv: parameter type and generate syntax
```

Interpretation:

```text
The AXI parser frontier moved through the detailed memory bridge. The next
blocker is the top-level burst splitter wrapper, separate from the granular
burst splitter shim already added earlier.
```

## Attempt 25: AXI Burst Splitter Wrapper S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_burst_splitter.sv
```

What changed:

```text
axi_burst_splitter.sv:
  added an S2_3_QUARTUS-only pass-through wrapper
  skipped the original type-parameterized wrapper in this mode
```

Important limitation:

```text
This is not a full semantic port of the burst splitter. It does not split
bursts, reject wrapping bursts, or reject ATOPs; it only forwards request and
response vectors.
```

Important progress:

```text
The previous axi_burst_splitter.sv type-parameter parser error is bypassed.
Quartus now reaches axi_demux.sv.
```

New first Quartus error:

```text
axi/src/axi_demux.sv:45
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_demux.sv: parameter type and interface wrapper
axi_err_slv.sv: parameter type and generate syntax
axi_multicut.sv: parameter type and generate syntax
```

Interpretation:

```text
The AXI parser frontier moved through the top-level burst splitter wrapper.
The next blocker is the top-level AXI demux wrapper, separate from the
axi_demux_simple shim already added earlier.
```

## Attempt 26: AXI Demux Wrapper S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_demux.sv
```

What changed:

```text
axi_demux.sv:
  added an S2_3_QUARTUS-only vector-boundary demux shim
  skipped the original type-parameterized wrapper and interface wrapper
```

Important limitation:

```text
This is not a full semantic port of the original AXI demux wrapper. It routes
the whole request vector by the selected port and returns one selected response
vector. It does not preserve channel-specific locking, ID tracking, or response
arbitration.
```

Important progress:

```text
The previous axi_demux.sv type-parameter and wrapper parser errors are
bypassed.
Quartus now reaches axi_err_slv.sv.
```

New first Quartus error:

```text
axi/src/axi_err_slv.sv:21
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_multicut.sv: parameter type and interface wrappers
axi_to_axi_lite.sv: parameter type
```

Interpretation:

```text
The AXI parser frontier moved through the top-level demux wrapper. The next
blocker is the AXI error slave helper.
```

## Attempt 27: AXI Error Slave S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_err_slv.sv
```

What changed:

```text
axi_err_slv.sv:
  added an S2_3_QUARTUS-only zero-response stub
  skipped the original type-parameterized error slave in this mode
```

Important limitation:

```text
This is not a full semantic port of the AXI error slave. It does not generate
valid DECERR/SLVERR AXI handshakes; it only drives the response vector to zero
for parser exploration.
```

Important progress:

```text
The previous axi_err_slv.sv type-parameter and generate parser errors are
bypassed.
Quartus now reaches axi_multicut.sv.
```

New first Quartus error:

```text
axi/src/axi_multicut.sv:24
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_to_axi_lite.sv: parameter type
axi_to_mem.sv: parameter type and localparam type
```

Interpretation:

```text
The AXI parser frontier moved through the error slave. The next blocker is the
multi-cut/register-slice helper.
```

## Attempt 28: AXI Multicut S2.3 Shim

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_multicut.sv
```

What changed:

```text
axi_multicut.sv:
  added an S2_3_QUARTUS-only vector pass-through shim
  skipped the original AXI cut chain and AXI/AXI-Lite interface wrappers
```

Important limitation:

```text
This is not a full semantic port of the multicut/register-slice chain. It does
not insert any timing cuts; request and response vectors are connected directly.
```

Important progress:

```text
The previous axi_multicut.sv type-parameter and wrapper parser errors are
bypassed.
Quartus now reaches axi_to_axi_lite.sv.
```

New first Quartus error:

```text
axi/src/axi_to_axi_lite.sv:27
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_to_mem.sv: parameter type and localparam type
axi_zero_mem.sv: parameter type and localparam type
axi_xbar_unmuxed.sv: parameter type
axi_to_mem_interleaved.sv: parameter type
```

Interpretation:

```text
The AXI parser frontier moved through multicut. The next blocker is the AXI to
AXI-Lite converter.
```

## Attempt 29: AXI to AXI-Lite S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_to_axi_lite.sv
```

What changed:

```text
axi_to_axi_lite.sv:
  added an S2_3_QUARTUS-only zero-output bridge stub
  skipped the original full converter, ID-reflect helper, and interface wrapper
```

Important limitation:

```text
This is not a full semantic port of the AXI to AXI-Lite converter. It does not
translate transactions; it drives both response and outgoing request vectors to
zero.
```

Important progress:

```text
The previous axi_to_axi_lite.sv type-parameter parser errors are bypassed.
Quartus now reaches axi_to_mem.sv.
```

New first Quartus error:

```text
axi/src/axi_to_mem.sv:21
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_zero_mem.sv: parameter type and localparam type
axi_xbar_unmuxed.sv: parameter type
axi_to_mem_interleaved.sv: parameter type and interface wrapper
```

Interpretation:

```text
The AXI parser frontier moved through the AXI to AXI-Lite converter. The next
blocker is the simpler AXI-to-memory wrapper.
```

## Attempt 30: AXI to Memory S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_to_mem.sv
```

What changed:

```text
axi_to_mem.sv:
  added an S2_3_QUARTUS-only no-request memory wrapper stub
  skipped the original type-parameterized wrapper and interface wrapper
```

Important limitation:

```text
This is not a full semantic port of the AXI-to-memory wrapper. It does not
translate AXI transactions into memory requests; it drives memory request
outputs and AXI response bits to zero.
```

Important progress:

```text
The previous axi_to_mem.sv type-parameter and localparam-type parser errors are
bypassed.
Quartus now reaches axi_zero_mem.sv.
```

New first Quartus error:

```text
axi/src/axi_zero_mem.sv:26
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_xbar_unmuxed.sv: parameter type
axi_to_mem_interleaved.sv: parameter type and interface wrapper
axi_xbar.sv: parameter type
fpu_div_sqrt_mvp/control_mvp.sv: unnamed block
axi_riscv_atomics/axi_res_tbl.sv: genvar parser error
```

Interpretation:

```text
The AXI parser frontier moved through the simple AXI-to-memory wrapper. The
run is now far enough to expose later non-AXI-library blockers as well, but the
first immediate blocker remains another AXI memory helper.
```

## Attempt 31: AXI Zero Memory S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_zero_mem.sv
```

What changed:

```text
axi_zero_mem.sv:
  added an S2_3_QUARTUS-only zero-response memory stub
  skipped the original type-parameterized zero-memory bridge
```

Important limitation:

```text
This is not a full semantic port of zero memory. It does not accept reads or
writes through valid AXI handshakes; it only drives busy low and response bits
to zero for parser exploration.
```

Important progress:

```text
The previous axi_zero_mem.sv type-parameter and localparam-type parser errors
are bypassed.
Quartus now reaches axi_xbar_unmuxed.sv.
```

New first Quartus error:

```text
axi/src/axi_xbar_unmuxed.sv:28
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_to_mem_interleaved.sv: parameter type and interface wrapper
axi_xbar.sv: parameter type
fpu_div_sqrt_mvp/control_mvp.sv: unnamed block
axi_riscv_atomics/axi_res_tbl.sv: genvar parser error
axi_riscv_atomics/axi_riscv_amos.sv: localparam/genvar parser errors
```

Interpretation:

```text
The AXI parser frontier moved through zero memory. The next blocker is the
unmuxed AXI crossbar.
```

## Attempt 32: AXI Unmuxed Crossbar S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_xbar_unmuxed.sv
```

What changed:

```text
axi_xbar_unmuxed.sv:
  added an S2_3_QUARTUS-only zero-output crossbar stub
  skipped the original type-parameterized crossbar and interface wrapper
```

Important limitation:

```text
This is not a full semantic port of the unmuxed AXI crossbar. It performs no
address decoding, no request routing, and no response routing; it drives crossbar
outputs to zero.
```

Important progress:

```text
The previous axi_xbar_unmuxed.sv type-parameter parser errors are bypassed.
Quartus now reaches axi_to_mem_interleaved.sv.
```

New first Quartus error:

```text
axi/src/axi_to_mem_interleaved.sv:20
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_xbar.sv: parameter type
fpu_div_sqrt_mvp/control_mvp.sv: unnamed block
axi_riscv_atomics/axi_res_tbl.sv: genvar parser error
axi_riscv_atomics/axi_riscv_amos.sv: localparam/genvar/unnamed-block parser errors
```

Interpretation:

```text
The AXI parser frontier moved through the unmuxed xbar. The next blocker is the
interleaved AXI-to-memory wrapper.
```

## Attempt 33: AXI Interleaved Memory S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_to_mem_interleaved.sv
```

What changed:

```text
axi_to_mem_interleaved.sv:
  added an S2_3_QUARTUS-only no-request memory wrapper stub
  skipped the original type-parameterized interleaved memory bridge and
  interface wrapper
```

Important limitation:

```text
This is not a full semantic port of the interleaved AXI-to-memory bridge. It
does not split read/write traffic or issue memory requests; it drives memory
request outputs and AXI response bits to zero.
```

Important progress:

```text
The previous axi_to_mem_interleaved.sv type-parameter and wrapper parser errors
are bypassed.
Quartus now reaches axi_xbar.sv.
```

New first Quartus error:

```text
axi/src/axi_xbar.sv:28
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
fpu_div_sqrt_mvp/control_mvp.sv: unnamed block
axi_riscv_atomics/*.sv: localparam, genvar, and unnamed-block parser errors
```

Interpretation:

```text
The AXI parser frontier moved through the interleaved memory bridge. The next
AXI blocker is the top-level crossbar wrapper. The run is also now consistently
showing later FPU and atomics parser issues.
```

## Attempt 34: AXI Top-Level Crossbar S2.3 Stub

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
snitch_cluster/.bender/git/checkouts/axi-*/src/axi_xbar.sv
```

What changed:

```text
axi_xbar.sv:
  added an S2_3_QUARTUS-only zero-output crossbar stub
  skipped the original type-parameterized crossbar and interface wrapper
```

Important limitation:

```text
This is not a full semantic port of the top-level AXI crossbar. It performs no
request routing, response routing, ID adaptation, or address decoding; it only
drives crossbar outputs to zero.
```

Important progress:

```text
The previous axi_xbar.sv type-parameter and wrapper parser errors are bypassed.
Quartus now reaches the FPU divider/square-root dependency.
```

New first Quartus error:

```text
fpu_div_sqrt_mvp/hdl/control_mvp.sv:2344
Error (10644): this block requires a name
```

Other errors in the same run:

```text
axi_riscv_atomics/*.sv: localparam, genvar, and unnamed-block parser errors
```

Interpretation:

```text
The parser frontier has moved out of the core AXI package. The remaining
reported blockers are now in the FPU divider/square-root dependency and the
AXI RISC-V atomics dependency.
```

## Attempt 35: FPU Divider Generate-Block Labels

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
snitch_cluster/.bender/git/checkouts/fpu_div_sqrt_mvp-*/hdl/control_mvp.sv
```

What changed:

```text
control_mvp.sv:
  named the outer divider iteration generate-for block
  named the inner mask-bit generate-for block
```

Important limitation:

```text
This is a syntax-only Quartus compatibility fix. It does not change the FPU
divider/square-root algorithm.
```

Important progress:

```text
The previous fpu_div_sqrt_mvp/control_mvp.sv unnamed-block errors are gone.
Quartus now reaches the AXI RISC-V atomics dependency.
```

New first Quartus error:

```text
axi_riscv_atomics/src/axi_res_tbl.sv:38
Error (10170): near text: "genvar"; expecting an identifier
```

Other errors in the same run:

```text
axi_riscv_atomics/*.sv: localparam and unnamed-block parser errors
```

Interpretation:

```text
The FPU divider/square-root file parsed past its first Quartus-only syntax
blocker. The next blocker class is AXI RISC-V atomics, which should be checked
against the one-core target before deciding between pruning, syntax porting, or
stub replacement.
```

## Attempt 36: Prune Unused AXI RISC-V Atomics Dependency

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

Manual source-list edits:

```text
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
removed the axi_riscv_atomics source block:
  axi_res_tbl.sv
  axi_riscv_amos_alu.sv
  axi_riscv_amos.sv
  axi_riscv_lrsc.sv
  axi_riscv_atomics.sv
  axi_riscv_lrsc_wrap.sv
  axi_riscv_amos_wrap.sv
  axi_riscv_atomics_wrap.sv
```

Why this is acceptable for this preflight:

```text
The one-core Snitch cluster Quartus source list does not include the simulation
testbench that instantiates axi_riscv_atomics_wrap. A design-side search found
no active instantiation of axi_riscv_atomics, axi_riscv_amos, axi_riscv_lrsc, or
axi_res_tbl outside that testbench/dependency block.
```

Important limitation:

```text
This does not port AXI RISC-V atomics to Quartus. It removes an unused
dependency from the educational S2.3 preflight.
```

Important progress:

```text
The previous axi_riscv_atomics parser errors are gone.
The source count dropped from 230 to 222 files.
Quartus now reaches the FPnew dependency.
```

New first Quartus error:

```text
fpnew/src/fpnew_cast_multi.sv:24
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
fpnew/*.sv: parameter type, localparam-in-parameter-list, and generate parser
errors
```

Interpretation:

```text
The parser frontier moved from unused AXI atomics into the active floating-point
unit stack. Because the one-core config currently uses rv32imafd plus Xssr/Xfrep,
FPnew is likely part of the intended design path, not just dead parser baggage.
```

## Attempt 37: Stub Snitch FPU Boundary and Prune FPnew Implementation

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
snitch_cluster/hw/snitch_cluster/src/snitch_fpu.sv
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
snitch_fpu.sv:
  added an S2_3_QUARTUS-only no-op FPU wrapper

source_list/snitch_cluster.flist-plus.in:
  removed fpu_div_sqrt_mvp implementation files
  removed FPnew implementation files
  kept fpnew_pkg.sv so Snitch FP package types/enums remain available
```

Important limitation:

```text
This is not a floating-point implementation and does not port FPnew to Quartus.
The S2_3_QUARTUS FPU wrapper accepts requests immediately, returns zero result
and zero status, forwards the tag, and mirrors input valid to output valid.
```

Important progress:

```text
The previous FPnew parameter-type parser errors are gone.
The previous snitch_fpu.sv TagType override parser error is bypassed.
The source count dropped from 222 to 201 files.
Quartus now reaches the register-interface/OpenTitan subregister dependency.
```

New first Quartus error:

```text
register_interface/vendor/lowrisc_opentitan/src/prim_subreg_arb.sv:28
Error (10170): near text: "if"; expecting "endmodule"
```

Other errors in the same run:

```text
prim_subreg_arb.sv: generate-if parser errors and repeated declarations after
parse recovery
apb_to_reg_v2.sv: parameter type parser error
```

Interpretation:

```text
The parser frontier moved beyond the floating-point implementation stack. The
next blocker class is the register-interface dependency, which includes
OpenTitan primitive subregister modules and type-parameterized register bridges.
```

## Attempt 38: Prune Register Bridge Variants and Label Subregister Generate

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
snitch_cluster/.bender/git/checkouts/register_interface-*/vendor/lowrisc_opentitan/src/prim_subreg_arb.sv
```

What changed:

```text
source_list/snitch_cluster.flist-plus.in:
  kept reg_intf.sv
  kept prim_subreg_arb.sv
  kept prim_subreg_ext.sv
  kept prim_subreg.sv
  kept deprecated/axi_to_reg.sv
  removed unused APB/reg bridge variants and prim_subreg_shadow.sv

prim_subreg_arb.sv:
  wrapped the conditional generate-if chain in explicit generate/endgenerate
```

Why this is acceptable for this preflight:

```text
The one-core Snitch cluster path actively uses deprecated axi_to_reg plus
prim_subreg/prim_subreg_ext. A design-side search did not find active users of
the removed APB/reg bridge variants in the selected file list.
```

Important limitation:

```text
This does not port the removed register bridge variants. It only narrows the
educational S2.3 preflight to the register-interface files that are reachable
from the current one-core cluster path.
```

Important progress:

```text
The previous prim_subreg_arb.sv generate-if parser errors are gone.
The source count dropped from 201 to 184 files.
Quartus now reaches the active deprecated AXI-to-register bridge.
```

New first Quartus error:

```text
register_interface/src/deprecated/axi_to_reg.sv:36
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
riscv-dbg/dm_csrs.sv and dm_mem.sv: unsupported inside expressions and parser
recovery errors
```

Interpretation:

```text
The parser frontier moved through the OpenTitan subregister primitive. The next
active bridge is axi_to_reg. The riscv-dbg block appears as the next broad
dependency class to check for reachability before patching.
```

## Attempt 39: Cut Peripheral Register Bridge and Prune Debug Dependency

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
snitch_cluster/hw/snitch_cluster/src/snitch_cluster.sv
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
snitch_cluster.sv:
  added an S2_3_QUARTUS peripheral-register boundary cut
  drives the ClusterPeripherals AXI slave response to zero
  drives the generated register request to zero
  skips deprecated axi_to_reg for the Quartus preflight

source_list/snitch_cluster.flist-plus.in:
  removed deprecated/axi_to_reg.sv
  removed the riscv-dbg dependency block
```

Why this is acceptable for this preflight:

```text
The riscv-dbg files had no design-side references in the one-core cluster path.
The deprecated axi_to_reg module is active, but it depends on type parameters
and already-pruned AXI-Lite/register bridge helpers. For this parser-frontier
experiment, cutting the peripheral-register bridge is more coherent than
reintroducing the full bridge stack.
```

Important limitation:

```text
This disables real AXI access to the cluster peripheral register file in the
S2_3_QUARTUS preflight. It is not a semantic bridge replacement.
```

Important progress:

```text
The previous axi_to_reg.sv parser errors are gone.
The previous riscv-dbg parser errors are gone.
The source count dropped from 184 to 172 files.
Quartus now reaches hw/future DMA/interconnect helpers.
```

New first Quartus error:

```text
hw/future/src/mem_to_axi_lite.sv:26
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
hw/future/src/dma/axi_dma_data_path.sv: generate parser error
hw/future/src/axi_interleaved_xbar.sv: parameter type and generate parser errors
```

Interpretation:

```text
The parser frontier moved beyond the active cluster peripheral register bridge
and the unused debug dependency. The next dependency class is hw/future, which
should be checked against the xdma:false one-core config before patching.
```

## Attempt 40: Prune Inactive hw/future Dependency Block

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

Manual source-list edits:

```text
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
removed the hw/future source block:
  mem_to_axi_lite.sv
  idma_reg64_frontend_reg_pkg.sv
  idma_tf_id_gen.sv
  dma/axi_dma_data_path.sv
  axi_interleaved_xbar.sv
  axi_zero_mem.sv
  idma_reg64_frontend_reg_top.sv
  idma_reg64_frontend.sv
  dma/axi_dma_data_mover.sv
  dma/axi_dma_burst_reshaper.sv
  dma/axi_dma_backend.sv
```

Why this is acceptable for this preflight:

```text
The selected wrapper sets Xdma to 1'b0, and the hw/future block is not referenced
outside its own helper files in the one-core cluster path. Keeping it in the
Quartus preflight only forced inactive DMA/interconnect parser errors.
```

Important limitation:

```text
This does not port the future iDMA/DMA helper stack. It removes inactive sources
from the educational S2.3 parser preflight.
```

Important progress:

```text
The previous hw/future parser errors are gone.
The source count dropped from 172 to 161 files.
Quartus now reaches the request/response interface dependency.
```

New first Quartus error:

```text
hw/reqrsp_interface/src/reqrsp_pkg.sv:28
Error (10170): near text: "inside"; expecting ")"
```

Other errors in the same run:

```text
axi_to_reqrsp.sv and reqrsp_cut.sv: parameter type parser errors
```

Interpretation:

```text
The parser frontier moved past inactive future/DMA helper files. The next class
is the request/response interface stack, which is active in the cluster path.
```

## Attempt 41: Port reqrsp Package Helper and Prune Unused Cut

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

Manual edits:

```text
snitch_cluster/hw/reqrsp_interface/src/reqrsp_pkg.sv
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
reqrsp_pkg.sv:
  replaced `amo inside {...}` with explicit equality comparisons joined by ||

source_list/snitch_cluster.flist-plus.in:
  removed hw/reqrsp_interface/src/reqrsp_cut.sv
```

Why this is acceptable for this preflight:

```text
The reqrsp_pkg.sv change preserves the same atomic-operation predicate while
avoiding a Quartus parser construct. reqrsp_cut.sv is not instantiated by the
selected one-core preflight path; keeping it only forced an inactive
parameter-type parser error.
```

Important limitation:

```text
This does not port the request/response bridge stack. It only fixes the active
package helper and removes one inactive helper file.
```

Important progress:

```text
The previous reqrsp_pkg.sv `inside` parser error is gone.
The previous reqrsp_cut.sv parser errors are gone.
The source count dropped from 161 to 160 files.
Quartus now reaches active request/response bridge and mux/demux modules.
```

New first Quartus error:

```text
hw/reqrsp_interface/src/axi_to_reqrsp.sv:29
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
axi_to_reqrsp.sv: parameter type, packed type alias, and assignment-pattern errors
reqrsp_demux.sv: parameter type and generate parser errors
```

Interpretation:

```text
The parser frontier moved from a small package expression into active
request/response interface modules. The next decision is whether to port these
module boundaries directly or cut a higher request/response boundary in the
educational Quartus preflight.
```

## Attempt 42: Black-Box reqrsp Bridge Implementations

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

Manual source-list edits:

```text
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
removed these request/response implementation files from the S2.3 Quartus
preflight list:
  hw/reqrsp_interface/src/axi_to_reqrsp.sv
  hw/reqrsp_interface/src/reqrsp_demux.sv
  hw/reqrsp_interface/src/reqrsp_iso.sv
  hw/reqrsp_interface/src/reqrsp_mux.sv
  hw/reqrsp_interface/src/reqrsp_to_axi.sv
  hw/tcdm_interface/src/axi_to_tcdm.sv
  hw/tcdm_interface/src/reqrsp_to_tcdm.sv
```

Why this is acceptable for this preflight:

```text
These files are active protocol bridges, not unused helpers. They are removed
only for the parser-frontier experiment so Quartus can continue into the next
unsupported dependency class. In a real implementation they would need to be
ported, replaced, or explicitly cut at a higher boundary.
```

Important limitation:

```text
This is a black-box/boundary cut, not a semantic reqrsp bridge port. The
preflight may later fail because these modules are unresolved or because their
surrounding behavior is missing.
```

Important progress:

```text
The previous axi_to_reqrsp.sv first blocker is gone.
The previous reqrsp_demux.sv parser errors are gone.
The source count dropped from 160 to 153 files.
Quartus now reaches the memory/TCDM interface boundary.
```

New first Quartus error:

```text
hw/mem_interface/src/mem_wide_narrow_mux.sv:33
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
mem_wide_narrow_mux.sv: parameter type and generate parser errors
mem_interface.sv: parameter type errors in MEM_BUS interfaces
tcdm_interface.sv: parameter type errors in TCDM_BUS interfaces
```

Interpretation:

```text
Quartus moved beyond the reqrsp bridge implementation files. The next class is
memory/TCDM wrappers and muxes that use parameterized interfaces and
type-parameterized module boundaries.
```

## Attempt 43: Black-Box Memory and TCDM Boundary Files

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

Manual source-list edits:

```text
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
removed these memory/TCDM implementation or interface files from the S2.3
Quartus preflight list:
  hw/mem_interface/src/mem_wide_narrow_mux.sv
  hw/mem_interface/src/mem_interface.sv
  hw/tcdm_interface/src/tcdm_interface.sv
  hw/tcdm_interface/src/tcdm_mux.sv
```

Why this is acceptable for this preflight:

```text
These files expose another Quartus parser class: parameterized interface
wrappers and type-parameterized mux boundaries. Removing them lets the
experiment identify the next blocker after the memory/TCDM boundary.
```

Important limitation:

```text
This is not a memory/TCDM implementation. It black-boxes active components and
therefore cannot be treated as a working Snitch cluster.
```

Important progress:

```text
The previous mem_wide_narrow_mux.sv first blocker is gone.
The previous mem_interface.sv and tcdm_interface.sv parser errors are gone.
The source count dropped from 153 to 149 files.
Quartus now reaches the actual Snitch core RTL.
```

New first Quartus error:

```text
hw/snitch/src/snitch_regfile_ff.sv:55
Error (10170): near text: "for"; expecting "endmodule"
```

Other errors in the same run:

```text
snitch_lsu.sv: parameter type errors
snitch_l0_tlb.sv: parameter type and generate parser errors
snitch.sv: module import-list parser error
snitch_ptw.sv: parameter type errors
axi_dma_error_handler.sv: parameter type errors
```

Interpretation:

```text
The parser frontier is now at the real Snitch core and tightly coupled core
support blocks. Further progress either requires direct core compatibility
patches or an explicit decision to stop preserving core semantics.
```

## Attempt 44: Port Snitch Register File Generate Loop

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

Manual edits:

```text
snitch_cluster/hw/snitch/src/snitch_regfile_ff.sv
```

What changed:

```text
wrapped the read-port assignment generate loop in explicit generate/endgenerate
declared the genvar separately before the for-loop
```

Why this is acceptable:

```text
The change preserves the register-file behavior. It only rewrites the generate
loop into a Quartus-accepted style.
```

Important progress:

```text
The previous snitch_regfile_ff.sv generate-loop parser error is gone.
Quartus now reaches snitch_lsu.sv as the first core blocker.
```

New first Quartus error:

```text
hw/snitch/src/snitch_lsu.sv:15
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
snitch_lsu.sv: parameter type errors
snitch_l0_tlb.sv: parameter type and generate parser errors
snitch.sv: module import-list parser error
snitch_ptw.sv: parameter type errors
axi_dma_error_handler.sv and axi_dma_perf_counters.sv: parameter type errors
```

Interpretation:

```text
The first syntax-only Snitch core issue is fixed. The next issue is harder:
Snitch LSU uses type parameters for tags and request/response channel structs.
That cannot be fixed with only a generate-style rewrite.
```

## Attempt 45: Port Snitch LSU Boundary for Quartus

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

Manual edits:

```text
snitch_cluster/hw/snitch/src/snitch_lsu.sv
snitch_cluster/hw/snitch/src/snitch.sv
snitch_cluster/hw/snitch_cluster/src/snitch_fp_ss.sv
```

What changed:

```text
snitch_lsu.sv:
  added an S2_3_QUARTUS module header using explicit widths instead of
  parameter type
  recreated the reqrsp request/response structs internally from AddrWidth and
  DataWidth
  kept the original typed-parameter LSU header for non-S2_3 builds
  routed LSU logic through internal data_req/data_rsp aliases

snitch.sv and snitch_fp_ss.sv:
  pass TagWidth under S2_3_QUARTUS instead of type parameters
  keep the original dreq_t/drsp_t/tag_t overrides outside S2_3_QUARTUS
```

Why this is acceptable:

```text
This preserves the LSU datapath and handshake logic. It only changes the
Quartus-facing module boundary so the active LSU does not require parameter
type syntax.
```

Important limitation:

```text
The S2_3_QUARTUS LSU wrapper assumes the connected data request/response
channels use the standard reqrsp packed layout derived from AddrWidth and
DataWidth.
```

Important progress:

```text
The previous snitch_lsu.sv parameter-type parser errors are gone.
Quartus now reaches snitch_l0_tlb.sv as the first core blocker.
```

New first Quartus error:

```text
hw/snitch/src/snitch_l0_tlb.sv:11
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
snitch_l0_tlb.sv: parameter type and generate parser errors
snitch.sv: module import-list parser error
snitch_ptw.sv: parameter type errors
axi_dma_error_handler.sv and axi_dma_perf_counters.sv: parameter type errors
```

Interpretation:

```text
The LSU is the first active Snitch core block ported without black-boxing. The
next active core-support block is the L0 TLB, which has the same type-parameter
pattern plus generate syntax that Quartus rejects.
```

## Attempt 46: Port Snitch L0 TLB Boundary for Quartus

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

Manual edits:

```text
snitch_cluster/hw/snitch/src/snitch_l0_tlb.sv
snitch_cluster/hw/snitch/src/snitch.sv
```

What changed:

```text
snitch_l0_tlb.sv:
  added an S2_3_QUARTUS module header using AddrWidth-derived vector ports for
  pa_o and pte_i instead of parameter type ports
  recreated pa_t and l0_pte_t internally with SNITCH_VM_TYPEDEF
  routed the TLB logic through internal pa/pte_refill aliases
  wrapped top-level generate-for and generate-if constructs in explicit
  generate/endgenerate blocks
  kept the original typed-parameter TLB header outside S2_3_QUARTUS

snitch.sv:
  passes AddrWidth to snitch_l0_tlb under S2_3_QUARTUS
  keeps the original pa_t/l0_pte_t type overrides outside S2_3_QUARTUS
```

Why this is acceptable:

```text
This preserves the L0 TLB lookup/refill behavior. It only changes the
Quartus-facing type-parameter boundary and generate syntax.
```

Important limitation:

```text
The S2_3_QUARTUS TLB wrapper assumes the connected VM packed types match the
standard SNITCH_VM_TYPEDEF layout for the selected AddrWidth.
```

Important progress:

```text
The previous snitch_l0_tlb.sv parameter-type parser error is gone.
The previous snitch_l0_tlb.sv generate parser errors are gone.
Quartus now reaches the snitch.sv module import list as the first blocker.
```

New first Quartus error:

```text
hw/snitch/src/snitch.sv:13
Error (10170): near text: "import"; expecting ";"
```

Other errors in the same run:

```text
snitch_ptw.sv: parameter type errors
snitch_dma helper files: parameter type errors
snitch_icache_l0.sv: generate parser errors
```

Interpretation:

```text
The second active Snitch core-support block is ported without black-boxing. The
next front-door issue is Quartus rejecting import declarations in the snitch
module header.
```

## Attempt 47: Move Snitch Module Imports for Quartus

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

Manual edits:

```text
snitch_cluster/hw/snitch/src/snitch.sv
```

What changed:

```text
under S2_3_QUARTUS:
  import snitch_pkg::* and riscv_instr::* at compilation-unit scope
  use a plain module snitch #(...) header

outside S2_3_QUARTUS:
  keep the original module snitch import ... #(...) header
```

Why this is acceptable:

```text
This is a syntax-only relocation of package imports for the Quartus path. It
does not change the Snitch core logic.
```

Important progress:

```text
The previous snitch.sv module import-list parser error is gone.
Quartus now reaches the Snitch module's own type parameters.
```

New first Quartus error:

```text
hw/snitch/src/snitch.sv:52
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
snitch.sv: type-parameter, generate, and inside-expression parser errors
snitch_ptw.sv: parameter type errors
snitch_dma helper files: parameter type errors
snitch_icache_l0.sv: generate parser errors
```

Interpretation:

```text
The import syntax issue was superficial. The next blocker is the main Snitch
core module boundary, which exposes multiple type parameters for data,
accelerator, and virtual-memory structs.
```

## Attempt 48: Port Main Snitch Module Boundary for Quartus

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

Manual edits:

```text
snitch_cluster/hw/snitch/src/snitch.sv
snitch_cluster/hw/snitch_cluster/src/snitch_cc.sv
```

What changed:

```text
snitch.sv:
  added S2_3_QUARTUS width parameters for data req/rsp, accelerator req/rsp,
  physical-address, and page-table-entry ports
  recreated reqrsp, VM, and accelerator packed structs internally
  routed the core body through internal aliases:
    acc_qreq / acc_prsp
    data_req / data_rsp
    ptw_ppn / ptw_pte
  kept the original typed-parameter boundary outside S2_3_QUARTUS

snitch_cc.sv:
  stops passing Snitch type parameters under S2_3_QUARTUS
  keeps the original type overrides outside S2_3_QUARTUS
```

Why this is acceptable:

```text
The Snitch core logic still operates on the same packed fields internally. The
change only replaces type-parameterized external ports with explicitly sized
packed-vector ports in the Quartus path.
```

Important limitation:

```text
The S2_3_QUARTUS Snitch boundary assumes the surrounding packed structs match
the standard local layouts for reqrsp, VM, and accelerator channels.
```

Important progress:

```text
The previous snitch.sv type-parameter parser errors are gone.
Quartus now parses into the Snitch core body and reaches generate-if syntax.
```

New first Quartus error:

```text
hw/snitch/src/snitch.sv:381
Error (10170): near text: "if"; expecting "endmodule"
```

Other errors in the same run:

```text
snitch.sv: generate-if parser errors
snitch.sv: inside-expression parser errors
snitch_ptw.sv: parameter type errors
snitch_dma helper files: parameter type errors
snitch_icache_l0.sv: generate parser errors
```

Interpretation:

```text
The main Snitch module boundary is now past Quartus. Remaining Snitch errors
are ordinary body syntax incompatibilities such as explicit generate blocks and
rewriting `inside` expressions.
```

## Attempt 49: Port Snitch Top-Level Generate Syntax

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

Manual edits:

```text
snitch_cluster/hw/snitch/src/snitch.sv
```

What changed:

```text
wrapped these top-level generate constructs in explicit generate/endgenerate:
  DebugSupport debug CSR block
  VMSupport ITLB block
  ALU operand reverse genvar loop
  VMSupport DTLB block

rewrote the ALU reverse loop to declare the genvar separately
```

Why this is acceptable:

```text
This is a syntax-only rewrite. The selected generated hardware is unchanged.
```

Important progress:

```text
The previous snitch.sv generate-if parser errors are gone.
The previous snitch.sv top-level genvar-loop parser error is gone.
Quartus now reaches unsupported inside expressions in the Snitch decoder.
```

New first Quartus error:

```text
hw/snitch/src/snitch.sv:930
Error (10170): near text: "inside"; expecting ")"
```

Other errors in the same run:

```text
snitch.sv: multiple inside-expression parser errors
snitch_ptw.sv: parameter type errors
snitch_dma helper files: parameter type errors
snitch_icache_l0.sv: generate parser errors
```

Interpretation:

```text
The Snitch core body now parses past top-level generate syntax. The next class
is membership tests written with SystemVerilog `inside`.
```

## Attempt 50: Rewrite Snitch inside Expressions

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

Manual edits:

```text
snitch_cluster/hw/snitch/src/snitch.sv
```

What changed:

```text
added local predicate functions for repeated instruction membership tests:
  scalar/vector divsqrt checks
  control-transfer instruction checks

replaced all `inside { ... }` expressions in snitch.sv with explicit
comparisons or predicate function calls

removed the stray semicolon after CheckPMANonIdempotent ASSERT_INIT because the
assertion macro expands to nothing under S2_3_QUARTUS
```

Why this is acceptable:

```text
The rewritten predicates preserve the same membership checks while avoiding
Quartus' unsupported `inside` expression syntax.
```

Important progress:

```text
The previous snitch.sv inside-expression parser errors are gone.
The late snitch.sv assertion-macro empty-item parser error is gone.
Quartus now reaches snitch_ptw.sv as the first blocker.
```

New first Quartus error:

```text
hw/snitch_vm/src/snitch_ptw.sv:14
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
snitch_dma helper files: parameter type errors
snitch_icache_l0.sv: generate parser errors
```

Interpretation:

```text
The main Snitch core source now parses through Quartus' front end. The next
active VM support block is the page-table walker.
```

## Attempt 51: Port Snitch PTW Boundary for Quartus

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

Manual edits:

```text
snitch_cluster/hw/snitch_vm/src/snitch_ptw.sv
snitch_cluster/hw/snitch_cluster/src/snitch_hive.sv
```

What changed:

```text
snitch_ptw.sv:
  added an S2_3_QUARTUS module header using explicit vector widths for pte_o
  and the reqrsp memory channel
  recreated reqrsp and VM packed structs internally
  routed PTW logic through pte_result, data_req, and data_rsp aliases
  kept the original typed-parameter PTW header outside S2_3_QUARTUS

snitch_hive.sv:
  stops passing PTW type parameters under S2_3_QUARTUS
  keeps the original type overrides outside S2_3_QUARTUS
```

Why this is acceptable:

```text
The PTW state machine and memory-access logic are preserved. Only the Quartus
module boundary is rewritten away from parameter type syntax.
```

Important limitation:

```text
The S2_3_QUARTUS PTW wrapper assumes the VM and reqrsp packed-vector layouts
match SNITCH_VM_TYPEDEF and REQRSP_TYPEDEF_ALL for the selected widths.
```

Important progress:

```text
The previous snitch_ptw.sv parameter-type parser error is gone.
Quartus now reaches the Snitch DMA helper files as the first blocker.
```

New first Quartus error:

```text
hw/snitch_dma/src/axi_dma_error_handler.sv:15
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
snitch_dma helper files: parameter type and generate parser errors
snitch_icache_l0.sv: generate parser errors
```

Interpretation:

```text
The active VM page-table walker is now past Quartus. The next reported class is
DMA helper RTL, which should be checked against the selected xdma:false config
before doing any direct port.
```

## Attempt 52: Prune Inactive Snitch DMA Implementations

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

Manual source-list edits:

```text
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
kept:
  hw/snitch_dma/src/axi_dma_pkg.sv

removed:
  hw/snitch_dma/src/axi_dma_error_handler.sv
  hw/snitch_dma/src/axi_dma_perf_counters.sv
  hw/snitch_dma/src/axi_dma_twod_ext.sv
  hw/snitch_dma/src/axi_dma_tc_snitch_fe.sv
```

Why this is acceptable for this preflight:

```text
The generated one-core wrapper sets Xdma to 1'b0, matching cfg/one-core.hjson
xdma:false. The DMA implementation files are only instantiated under the
inactive Xdma generate branch, while axi_dma_pkg.sv is still needed for shared
type definitions.
```

Important limitation:

```text
This does not port the Snitch DMA engine. It removes inactive DMA
implementation sources from the educational S2.3 parser preflight.
```

Important progress:

```text
The previous snitch_dma implementation parser errors are gone.
The source count dropped from 149 to 145 files.
Quartus now reaches the instruction-cache L0 implementation.
```

New first Quartus error:

```text
hw/snitch_icache/src/snitch_icache_l0.sv:107
Error (10170): near text: "for"; expecting "endmodule"
```

Other errors in the same run:

```text
snitch_icache_l0.sv: top-level generate-for and generate-if parser errors
```

Interpretation:

```text
The parser frontier moved beyond inactive DMA implementation files. The next
active support block is the instruction-cache L0 module.
```

## Attempt 53: Port Snitch ICache L0 Generate Syntax

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

Manual edits:

```text
snitch_cluster/hw/snitch_icache/src/snitch_icache_l0.sv
```

What changed:

```text
wrapped these top-level generate constructs in explicit generate/endgenerate:
  tag compare loop
  tag/data array loop
  multihit detection generate-if
  instruction predecode loop

rewrote genvar declarations to the older separate-declaration style
```

Why this is acceptable:

```text
This is a syntax-only rewrite. The L0 instruction-cache compare, storage, and
predecode behavior is preserved.
```

Important progress:

```text
The previous snitch_icache_l0.sv generate parser errors are gone.
Quartus now reaches snitch_icache_refill.sv as the first blocker.
```

New first Quartus error:

```text
hw/snitch_icache/src/snitch_icache_refill.sv:10
Error (10170): near text: "type"; expecting an identifier
```

Other errors in the same run:

```text
snitch_icache_refill.sv: parameter type and generate parser errors
snitch_icache_lfsr.sv: generate parser errors
snitch_icache_lookup.sv: parameter type and generate parser errors
```

Interpretation:

```text
The L0 instruction-cache module is past Quartus. The next class is the rest of
the instruction-cache refill/lookup support stack.
```

## Attempt 54: Black-box Snitch ICache Preflight Files

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

Manual edits:

```text
source_list/snitch_cluster.flist-plus.in
```

What changed:

```text
removed these active instruction-cache implementation files from the Quartus
preflight source list:
  hw/snitch_icache/src/snitch_icache_refill.sv
  hw/snitch_icache/src/snitch_icache_lfsr.sv
  hw/snitch_icache/src/snitch_icache_lookup.sv
  hw/snitch_icache/src/snitch_icache_handler.sv
  hw/snitch_icache/src/snitch_icache.sv

kept these instruction-cache definition/L0 files:
  hw/snitch_icache/src/snitch_icache_pkg.sv
  hw/snitch_icache/src/snitch_icache_l0.sv
```

Why this is acceptable for this preflight:

```text
This is only acceptable for the S2.3 parser-frontier experiment. These are
active instruction-cache files, not inactive helper files. A real Snitch port
must either port this logic, replace it with an equivalent Quartus-compatible
implementation, or change the frontend memory architecture intentionally.
```

Important limitation:

```text
This does not port the Snitch instruction cache. It black-boxes active
instruction-cache refill/lookup/handler logic so the experiment can measure the
next unsupported Quartus parser frontier.
```

Important progress:

```text
The previous snitch_icache_refill.sv parameter-type first blocker is gone.
The snitch_icache_lfsr.sv and snitch_icache_lookup.sv parser errors are gone.
The source count dropped from 145 to 140 files.
Quartus now reaches the integer processing unit ALU.
```

New first Quartus error:

```text
hw/snitch_ipu/src/snitch_ipu_alu.sv:32
Error (10170): near text: "for"; expecting "endmodule"
```

Other errors in the same run:

```text
snitch_ipu_alu.sv: top-level generate-for and generate-if parser errors
snitch_ipu_alu.sv: repeated genvar/identifier declarations in later stages
```

Interpretation:

```text
The parser frontier moved beyond the active instruction-cache stack by
black-boxing it. The next active extension block is the integer processing unit
ALU, which still uses SystemVerilog generate forms Quartus rejects here.
```
