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

The first patch removes unsupported `parameter type` usage from the local
tech-cell SRAM files:

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
snitch_cluster/.bender/git/checkouts/tech_cells_generic-*/src/rtl/tc_sram.sv:114
Error (10170): near text: "if"; expecting "endmodule"
```

This matches the S2.2 overlay result, but now the fix exists as direct edits in
the local Snitch fork.
