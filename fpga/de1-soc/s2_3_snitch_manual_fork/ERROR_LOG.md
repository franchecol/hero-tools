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
