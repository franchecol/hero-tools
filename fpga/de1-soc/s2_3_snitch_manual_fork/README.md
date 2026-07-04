# S2.3 Manual Snitch Fork Experiment

This experiment is the manual follow-up to S2.2.

S2.2 proved that an overlay patch can move the first Quartus error, but the
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

The important distinction from S2.2:

```text
S2.2 generated patched copies with a script.
S2.3 edits the local Snitch fork directly.
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
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s2_3_snitch_manual_fork
./scripts/quartus_preflight.sh
```

## Current Result

Attempt 9 was run locally with Quartus Prime Lite 25.1std.0.

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
```

New first blocker:

```text
snitch_cluster/.bender/git/checkouts/common_cells-*/src/spill_register.sv:18
Error (10170): near text: "type"; expecting an identifier
```

The fix now exists as direct edits in the local Snitch fork. The next class is
common_cells stream/spill wrapper syntax porting: `spill_register`,
`stream_delay`, `stream_fifo`, `stream_fork_dynamic`, and
`fall_through_register`.
