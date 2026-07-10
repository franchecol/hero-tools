# Q2.3 Manual Snitch Fork Experiment

This experiment is the manual follow-up to Q2.2.

Q2.2 proved that an overlay patch can move the first Quartus error, but the
overlay script is not the right long-term shape if this becomes a large port.
This folder therefore contains an editable, pruned copy of the Snitch checkout:

```text
snitch_cluster/
```

The copy excludes generated Verilator/build output and nested Git metadata. It
keeps the source tree, the Bender dependency checkout contents, and the small
generated Snitch wrapper files needed by the Quartus preflight.

## Goal

```text
Start from the original generated Snitch cluster.
Manually edit the copied source tree for Quartus compatibility.
Run Quartus analysis/elaboration.
Record each blocker as it appears.
```

This is intentionally still a direct full-cluster experiment. It is separate
from the successful Snitch-Lite path.

## Current Manual Patch

The fork is being ported in small, committed parser-compatibility batches.
The first patch removed unsupported `parameter type` usage from the local
tech-cell SRAM files, then later patches handled generate syntax, macro syntax,
and Common Cells utility modules.

```text
snitch_cluster/.bender/git/checkouts/tech_cells_generic-*/src/rtl/tc_sram.sv
snitch_cluster/.bender/git/checkouts/tech_cells_generic-*/src/rtl/tc_sram_impl.sv
```

Because `tc_sram_impl` no longer accepts implementation-control type
parameters, its local call sites were also edited:

```text
snitch_cluster/hw/snitch_cluster/src/snitch_cluster.sv
snitch_cluster/hw/snitch_icache/src/snitch_icache_lookup.sv
```

The important distinction from Q2.2:

```text
Q2.2 generated patched copies with a script.
Q2.3 edits the local Snitch fork directly.
```

For a line-level view of what changed compared with the original Occamy/Bender
checkout, open:

```text
patches/attempt1_sram_type_parameter_port.patch
```

The preflight does not run Bender inside this fork. Instead it uses a frozen
file-list template:

```text
source_list/snitch_cluster.flist-plus.in
```

That is intentional: Bender-managed dependency checkouts would otherwise
recreate dependency Git trees and overwrite manual edits in `.bender/git`.

## Run

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/q2_3_snitch_manual_fork
./scripts/quartus_preflight.sh
```

## Current Result

Attempt 55 was run locally with Quartus Prime Lite 25.1std.0.

Result:

```text
FAIL
no .sof produced
```

Important progress:

```text
The original tc_sram.sv/tc_sram_impl.sv "parameter type" errors are gone.
The first generate-syntax errors in tc_sram.sv, generic_memory.sv,
cc_onehot.sv, and clk_int_div.sv are gone.
The default macro argument errors in registers.svh and assertions.svh are gone.
The first common_cells utility-module errors in credit_counter.sv,
delta_counter.sv, fifo_v3.sv, gray_to_binary.sv, heaviside.sv, and
isochronous_spill_register.sv are gone.
The second common_cells batch errors in lfsr.sv, lossy_valid_to_stream.sv,
onehot_to_bin.sv, passthrough_stream_fifo.sv, popcount.sv, ring_buffer.sv, and
rr_arb_tree.sv are gone.
The shift-register/spill-register errors in shift_reg.sv, shift_reg_gated.sv,
and spill_register_flushable.sv are gone.
The stream-helper errors in stream_fork.sv, stream_join_dynamic.sv,
stream_mux.sv, stream_throttle.sv, sub_per_hash.sv, and read.sv are gone.
The unused STREAM_DV interface helper was removed from the Quartus preflight
file list, reducing it from 312 to 311 source files.
The address-decoder errors in addr_decode_dync.sv are gone, and unused CDC
helper files were removed from the Quartus preflight file list. The source
count is now 302 files.
The active lzc.sv generate-syntax errors are gone, and another unused
Common Cells helper group was removed from the Quartus preflight file list.
The source count is now 296 files.
The stream/spill wrapper parser errors in spill_register.sv, stream_fifo.sv,
stream_fork_dynamic.sv, and fall_through_register.sv are gone. The unused
stream_delay.sv helper was removed from the preflight list, so the source count
is now 295 files.
The active stream_to_mem.sv type/generate errors are gone, and unused id_queue.sv
was removed from the preflight list. The source count is now 294 files.
The stream arbitration/xbar parser errors in stream_arbiter_flushable.sv,
stream_arbiter.sv, and stream_xbar.sv are gone. The unused
stream_fifo_optimal_wrap.sv and stream_register.sv helpers were removed from
the preflight list, so the source count is now 292 files.
The inactive mem_to_banks*.sv and stream_omega_net.sv helpers were removed
from the preflight list. The source count is now 289 files.
The deprecated Common Cells helper block was removed from the preflight list.
The source count is now 277 files.
The unused APB dependency block was removed from the preflight list.
The source count is now 271 files.
A conservative unused AXI helper slice was removed from the preflight list.
The source count is now 230 files.
The active axi_demux_id_counters.sv parser errors are gone.
The active axi_atop_filter.sv parser errors are gone.
The active axi_burst_splitter_gran.sv parser errors are bypassed with an
S2_3_QUARTUS single-beat pass-through shim.
The active axi_cut.sv parser errors are bypassed with an S2_3_QUARTUS
pass-through shim.
The active axi_demux_simple.sv parser errors are bypassed with an S2_3_QUARTUS
vector-boundary demux shim.
The active axi_id_prepend.sv parser errors are bypassed with an S2_3_QUARTUS
channel-vector pass-through shim.
The active axi_mux.sv parser errors are bypassed with an S2_3_QUARTUS
single-slave forwarding shim.
The active axi_to_detailed_mem.sv parser errors are bypassed with an
S2_3_QUARTUS no-request memory bridge stub.
The active axi_burst_splitter.sv parser errors are bypassed with an
S2_3_QUARTUS pass-through shim.
The active axi_demux.sv parser errors are bypassed with an S2_3_QUARTUS
vector-boundary demux shim.
The active axi_err_slv.sv parser errors are bypassed with an S2_3_QUARTUS
zero-response stub.
The active axi_multicut.sv parser errors are bypassed with an S2_3_QUARTUS
pass-through shim.
The active axi_to_axi_lite.sv parser errors are bypassed with an S2_3_QUARTUS
zero-output bridge stub.
The active axi_to_mem.sv parser errors are bypassed with an S2_3_QUARTUS
no-request memory wrapper stub.
The active axi_zero_mem.sv parser errors are bypassed with an S2_3_QUARTUS
zero-response memory stub.
The active axi_xbar_unmuxed.sv parser errors are bypassed with an S2_3_QUARTUS
zero-output crossbar stub.
The active axi_to_mem_interleaved.sv parser errors are bypassed with an
S2_3_QUARTUS no-request memory wrapper stub.
The active axi_xbar.sv parser errors are bypassed with an S2_3_QUARTUS
zero-output crossbar stub.
The active fpu_div_sqrt_mvp/control_mvp.sv unnamed generate-loop errors are
gone after adding explicit generate block labels.
The unused AXI RISC-V atomics dependency block was removed from the preflight
list. The source count is now 222 files.
The FPnew implementation files and FPU divider/square-root implementation files
were removed from the preflight list, leaving fpnew_pkg.sv for type definitions.
snitch_fpu.sv now has an S2_3_QUARTUS no-op FPU boundary stub. The source count
is now 201 files.
Unused register-interface bridge variants were removed from the preflight list,
and prim_subreg_arb.sv now has an explicit generate/endgenerate wrapper. The
source count is now 184 files.
The active AXI-to-register bridge is bypassed with an S2_3_QUARTUS
peripheral-register boundary cut inside snitch_cluster.sv, and the unused
riscv-dbg dependency block was removed from the preflight list. The source count
is now 172 files.
The inactive hw/future DMA/interconnect helper block was removed from the
preflight list. The source count is now 161 files.
The reqrsp_pkg.sv atomic-operation helper no longer uses the unsupported
SystemVerilog `inside` expression, and the unused reqrsp_cut.sv helper was
removed from the preflight list. The source count is now 160 files.
The request/response bridge implementation files and the AXI-to-TCDM wrapper
were removed from the Q2.3 preflight source list as black-box/boundary
candidates. The source count is now 153 files.
The memory/TCDM interface and mux implementation files were also removed from
the Q2.3 preflight source list as black-box/boundary candidates. The source
count is now 149 files.
snitch_regfile_ff.sv now uses an explicit generate/endgenerate block with a
separately declared genvar for the read-port assignment loop.
snitch_lsu.sv now has an S2_3_QUARTUS width-parameterized port wrapper that
keeps the LSU logic intact while avoiding type parameters at the module
boundary.
snitch_l0_tlb.sv now has an S2_3_QUARTUS width-parameterized VM boundary and
explicit generate/endgenerate blocks while preserving the TLB logic.
snitch.sv now moves package imports out of the module header under
S2_3_QUARTUS, avoiding Quartus' module-import-list parser limitation.
snitch.sv now has an S2_3_QUARTUS width-parameterized boundary for data,
accelerator, and VM ports while preserving internal packed-struct logic.
snitch.sv top-level debug, ITLB, ALU reverse-loop, and DTLB generate blocks now
use explicit generate/endgenerate syntax.
snitch.sv no longer uses unsupported `inside` membership tests, and the one
S2_3-empty assertion macro call no longer leaves a stray semicolon.
snitch_ptw.sv now has an S2_3_QUARTUS width-parameterized VM/reqrsp boundary
while preserving the page-table-walker logic.
Inactive Snitch DMA implementation files were removed from the Q2.3 preflight
source list while keeping axi_dma_pkg.sv for shared type definitions. The
source count is now 145 files.
snitch_icache_l0.sv top-level compare, array, multihit, and predecode generate
blocks now use explicit generate/endgenerate syntax.
The active instruction-cache refill, lookup, handler, LFSR, and top-level
implementation files were removed from the Q2.3 preflight source list as
black-box/boundary candidates. This is not a semantic port of the instruction
cache. The source count is now 140 files.
snitch_ipu_alu.sv top-level RV32B/RV32BFull generate-if blocks and generate-for
loops now use explicit generate/endgenerate syntax with separately declared,
unique genvars.
```

New first blocker:

```text
snitch_cluster/hw/snitch_ipu/src/snitch_int_ss.sv:7
Error (10170): near text: "import"; expecting ";"
```

The next class is the Snitch integer subsystem boundary and the SSR block's
type-parameterized interfaces.
