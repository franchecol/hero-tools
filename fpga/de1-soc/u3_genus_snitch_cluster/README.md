# U3: Upstream One-Core Snitch Cluster Through Genus

U3 is the first external-synthesis experiment that moves above the standalone
Snitch core. It feeds the generated wrapper for the original upstream
`snitch_cluster` module, together with its complete Bender dependency graph,
into Cadence Genus.

```text
one-core-integer.hjson
          │ upstream clustergen.py
          ▼
generated de1_u3_snitch_cluster_wrapper
          │ upstream Bender Genus manifest
          ▼
original snitch_cluster + AXI + TCDM + I-cache + dependencies
          │
          ▼
Genus elaboration → generic synthesis
```

## Scope

The configuration deliberately removes optional compute features while keeping
the upstream cluster architecture intact:

```text
cores:                  1
core ISA:               RV32IMA
TCDM:                   16 KiB, 4 banks
instruction cache:      4 KiB, two-way set associative
virtual memory:         disabled
external debug:         disabled
FPU/SSR/FREP/XDMA:      disabled
narrow/wide AXI ports:  retained by the upstream wrapper
```

Four TCDM banks are the architectural minimum for a 64-bit narrow bus and a
64-bit wide bus in this revision. This is not a custom replacement cluster and
does not patch upstream RTL.

The I-cache is 4 KiB and two-way set associative because this is the smallest
geometry satisfying two upstream implementation constraints. It produces a
24-bit tag RAM, which fits `tc_sram`'s complete 8-bit lanes, and a nonzero-width
replacement LFSR. Direct-mapped `sets=1` produces an illegal zero-bit LFSR in
this RTL revision.

This pinned generator revision emits illegal zero-width `SsrCfgs` and `SsrRegs`
arrays when `Xssr` is disabled. `normalize_zero_ssr.py` changes only that
generated artifact to contain one inert zeroed slot and sets `NumSsrsMax=1`.
The core still has `Xssr=0`; no SSR hardware is enabled. The normalizer is
fail-fast and stops if the expected generated text is not found exactly once.

## Decision Gates

```text
Gate 1  clustergen accepts the reduced configuration
Gate 2  Bender emits the complete native Genus source script
Gate 3  Genus parses and elaborates the upstream cluster wrapper
Gate 4  Genus completes generic synthesis
Gate 5  only then design a Cyclone V boundary and assess device fit
```

U3 records each real failing gate and its minimal resolution. A Quartus wrapper
or gate-level import is intentionally deferred to U4 because Genus first had to
prove that the whole reduced upstream cluster can become a generic netlist.

Bender expects the generated wrapper under
`target/snitch_cluster/generated/` in the server checkout. The deployment
places the U3-generated wrapper there before requesting the native Genus
script; this updates a generated artifact, not upstream source RTL.

The generated Bender script uses Genus Common UI commands and must be run
without `-legacy_ui`. Mixing that script with legacy UI makes legal modern
SystemVerilog constructs appear as parser errors.

## Reproduce

Generate the wrapper and inspect the memory structures locally:

```bash
./scripts/generate.sh
```

Run the Genus feasibility gate on the university server:

```bash
./scripts/deploy_and_run_lab.sh
```

## Status

```text
Configuration generation:  PASS
Bender Genus manifest:      PASS
SystemVerilog parsing:      PASS
Genus elaboration:          PASS
Genus generic synthesis:    PASS
Quartus import/fit:          not started
Physical FPGA test:         not started
```

The final generic netlist contains 415,192 instances and has SHA-256:

```text
0bb23b13e1172e8bcf0208caa86cebbf5a6570257b22f4d6aa21c759fd90550c
```

Genus reported zero errors and 195 warnings. Generic synthesis took about 55
minutes and peaked near 9.2 GiB. See
[`captures/u3_genus_2026-07-10.txt`](captures/u3_genus_2026-07-10.txt) for the
complete concise evidence.

The 415,192-instance result is not a Cyclone V fit estimate. The generic
`tc_sram` models expanded into registers and logic. U4 must preserve the
upstream memory interfaces but replace their implementation boundary with
Quartus-inferable M10K memories before attempting a meaningful fit.
