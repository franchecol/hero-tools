# U0: Direct Genus Snitch-Core Probe

U0 is the first escalation after the X0 toy gate-level import passed on the
physical DE1-SoC.

```text
Original upstream Snitch SystemVerilog
  -> Cadence Genus frontend and synthesis
  -> TSMC65 mapped gate-level netlist
  -> Questa gate-level simulation
  -> Quartus compatibility analysis
  -> Cyclone V implementation if the compatibility gate passes
```

## Question

```text
Can Genus directly elaborate and synthesize the real upstream Snitch integer
core source set without first translating it through sv2v?
```

This is the meaningful test of the professor-proposed path.  Passing the
already translated SL3 Verilog to Genus would not test whether Genus solves the
original SystemVerilog frontend problem.

## Exact Upstream Revisions

```text
snitch_cluster
  repository: https://github.com/pulp-platform/snitch_cluster.git
  revision:   8cae8d282bc12be4993c0e6c51161374f924c92b

common_cells
  repository: https://github.com/pulp-platform/common_cells.git
  revision:   1281545696eb3fcba50ec5b4275993476a3c710e
```

These are the revisions selected by the local Occamy/Snitch dependency locks.

## Scope

The probe instantiates the upstream `snitch` module directly with:

```text
one RV32E integer core
dynamic instruction input
observable instruction-fetch output
observable data-request output
no FPU
no DMA
no SSR
no IPU
no virtual memory
no debug module
no AXI fabric
no TCDM interconnect
no cluster wrapper
```

Dynamic instruction input and observable request outputs are important.  They
keep meaningful decoder, register-file, ALU, control-flow, CSR, and load/store
logic alive during synthesis instead of allowing the core to collapse into the
constant-NOP shell measured by SL3.

## Lab Files

```text
lab/snitch_core_shims.sv
  Minimal definitions for package types referenced by the reduced core.

lab/snitch_genus_probe.sv
  Flat-port synthesis wrapper around the upstream snitch module.

lab/genus_snitch_core.tcl
  Genus source order, TSMC65 library, synthesis, and report commands.

lab/snitch_core_gate_tb.sv
  Gate-level reset and sequential instruction-fetch test.

scripts/run_lab.sh
  Command sequence to execute after the files and repositories are present on
  the university server.

scripts/run_gate_sim_lab.sh
  Questa compilation and simulation with the TSMC65 Verilog cell model.
```

## Lab Layout

```text
~/snitch_gatelevel_lab/s17/
├── common_cells/
├── snitch_cluster/
├── genus_snitch_core.tcl
├── snitch_core_shims.sv
└── snitch_genus_probe.sv
```

## Decision Gates

```text
Gate 1: Genus parse/elaboration
  Did Genus accept the original package, struct, type-parameter, and module
  syntax and elaborate top snitch_genus_probe?

Gate 2: Generic synthesis
  Did syn_generic preserve a meaningful core rather than optimize it away?

Gate 3: TSMC65 mapping
  Did syn_map emit a complete mapped structural netlist?

Gate 4: Gate-level simulation
  Does the mapped core reset and issue the expected instruction requests in
  Questa with the TSMC65 cell model?

Gate 5: Quartus compatibility
  How many distinct TSMC65 cell modules and special constructs must be adapted
  before Quartus can elaborate the mapped netlist?
```

The first failing gate is a result and must be recorded.  The experiment does
not assume in advance that the full mapped core will be portable to Cyclone V.

## Current Status

```text
X0 physical toy proof:                  PASS
Pinned Snitch repository on lab server: PASS
Pinned common_cells on lab server:      PASS
U0 direct Genus elaboration:            PASS
U0 generic synthesis:                   PASS
U0 TSMC65 mapping:                      PASS
U0 mapped cell instances:               3296
U0 mapped cell area:                    12413.520
U0 mapped netlist size:                 447 KiB
U0 Questa gate-level simulation:        PASS
U0 valid fetches observed:               16
U0 highest fetch address:                0x40
U0 Questa errors/warnings:               0 / 0
U0 Quartus generic import:                PASS
U0 Quartus resources:                     1216 ALMs / 988 registers
U0 Quartus 50 MHz worst setup slack:      0.244 ns
U0 JTAG programming:                      PASS
U0 physical LED/reset observation:        PASS
```

The first Genus attempt failed before reading the RTL correctly because legacy
`read_hdl` does not accept the attempted `-incdir` form.  The corrected script
uses the `init_hdl_search_path` root attribute.  This distinction matters: the
first error was a command-interface mistake, not an unsupported Snitch
SystemVerilog construct.

See `captures/s17_genus_questa_2026-07-10.txt` for the compact evidence.

## Next Compatibility Experiment

The mapped netlist uses 3296 instances across many TSMC65 cell types.  Repeating
X0's hand-written shim method for every cell would be brittle and would mix
cell-library translation work with the architectural portability question.

The next controlled input to Quartus is therefore a Genus generic structural
netlist written immediately after `syn_generic`:

```text
original Snitch SystemVerilog
  -> Genus read/elaborate
  -> Genus syn_generic
  -> generic structural Verilog
  -> Quartus Cyclone V synthesis
```

If Quartus accepts that generic netlist, Genus has served as the stronger
SystemVerilog frontend while Quartus remains responsible for mapping onto FPGA
LUTs, registers, and memories.  The TSMC65 mapped netlist remains the independent
gate-level simulation reference.

The first direct Quartus run parsed and elaborated all six Genus entities, then
Quartus 25.1 crashed in its internal name-generation subsystem with
`dimension == 0`.  The trigger is Genus's escaped identifiers for flattened
multidimensional struct fields, not an unsupported logic primitive.  The next
retry mechanically replaces only escaped identifier tokens with deterministic
hexadecimal names through `scripts/sanitize_genus_identifiers.py`; connectivity
and logic are unchanged.

The sanitized retry passed the full Quartus flow.  Auto Fit initially missed
the 50 MHz requirement by 0.026 ns.  Standard Fit closed timing with 0.244 ns
worst-case setup slack.  The resulting design uses 1216 ALMs (4%) and 988
registers, and JTAG programming of `5CSEMA5F31@2` passed with zero errors.
The user then physically confirmed the expected reset indication: `LEDR[9]`
stays on while reset is released and turns off while `KEY[0]` is pressed.

See `captures/s17_quartus_program_2026-07-10.txt` for the compact Quartus and
programmer evidence.

## Reproduce The Local Import

Fetch and checksum the Genus generic netlist from the lab server:

```bash
./scripts/fetch_generic_netlist.sh
```

Build and program:

```bash
./scripts/build_quartus.sh
./scripts/program.sh
```

The build script verifies the original Genus artifact hash, regenerates the
identifier-sanitized Quartus input, and then starts Quartus.  Neither generated
netlist nor Quartus output is committed.
