# Snitch-Lite S2: Quartus Wrapper Preflight

S2 starts the DE1-SoC Quartus-facing path for the reduced real Snitch target.

S0 proved the generated real Snitch RTL can boot and execute a tiny program in
Verilator. S1 proved the same target can issue a peripheral-style store. S2
does not claim the Snitch target fits or fully synthesizes on DE1-SoC yet. It
answers the next practical question:

```text
Can we package the generated one-core Snitch RTL as a Quartus project?
```

## What This Adds

```text
cfg/one-core.hjson
  Reduced one-core Snitch config reused from S0/S1.

rtl/de1_s2_snitch_quartus_wrapper.sv
  Thin DE1 top that instantiates snitch_cluster_wrapper.

scripts/export_quartus_project.sh
  Generates Snitch RTL, asks Bender for the RTL file list, converts it to QSF,
  and writes a local Quartus project.

scripts/quartus_preflight.sh
  Runs Quartus analysis and elaboration on the generated project. The full
  Quartus log is written to generated/quartus_map_preflight.log.
```

## Generate The Quartus Project

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s2_snitch_quartus_wrapper
./scripts/export_quartus_project.sh
```

Generated files are placed under:

```text
generated/
```

They are intentionally ignored by git because they contain absolute paths into
the local Bender checkout.

## Run Quartus Preflight

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s2_snitch_quartus_wrapper
./scripts/quartus_preflight.sh
```

This runs:

```text
quartus_map --analysis_and_elaboration de1_s2_snitch_quartus_wrapper
```

## Pass Criteria

S2 has two levels:

```text
Level A:
  export_quartus_project.sh succeeds
  generated/de1_s2_snitch_quartus_wrapper.qsf exists
  generated/snitch_sources.qsf contains the Bender-derived RTL list

Level B:
  quartus_preflight.sh succeeds
  Quartus can analyze/elaborate the generated Snitch wrapper
```

If Level B fails, that is still useful. The first Quartus error tells us whether
the next work is a SystemVerilog compatibility issue, a missing file/include, a
memory primitive issue, or simply that this reduced Snitch target is still too
large/ASIC-oriented for Cyclone V.

## Verified Result

Verified locally on 2026-07-02 with Quartus Prime Lite 25.1std.0:

```text
Level A:
  PASS
  export_quartus_project.sh generated the Quartus project.
  Bender export contained:
    include_dirs=9
    defines=4
    files=312

Level B:
  FAIL, but for a useful next-step reason.
  Quartus now finds the wrapper and the Snitch dependency files.
  The first real blocker is Quartus Lite SystemVerilog compatibility.
```

The first failing Quartus error is:

```text
Error (10170): Verilog HDL syntax error at tc_sram.sv(69) near text: "type";
expecting an identifier ("type" is a reserved keyword).
```

That line is a SystemVerilog type parameter:

```systemverilog
parameter type addr_t = logic [AddrWidth-1:0],
```

So S2 currently proves that the project packaging path works, but the unmodified
real Snitch RTL is not directly accepted by Quartus Lite analysis/elaboration
yet.

## Translation Follow-Up

The follow-up translation experiment is documented in:

```text
TRANSLATION_EXPERIMENT.md
```

Summary:

```text
sv2v and yosys were installed and verified.
Full snitch_cluster_wrapper translation was attempted.
The path is not recommended to continue because it requires filtering,
patching, assertion skipping, and still fails inside real cluster RTL.
```

## Why This Is Not Yet S3

S3 should connect Snitch-visible behavior to board-visible LED/UART/register
logic. S2 first checks whether Quartus can even accept the generated Snitch RTL
package.
