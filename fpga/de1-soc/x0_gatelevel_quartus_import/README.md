# X0: Gate-Level Netlist Import Probe

This experiment tests the professor's proposed path in the smallest useful form:

```text
RTL toy design
  -> Genus synthesis with a TSMC65 Liberty library
  -> gate-level Verilog netlist
  -> thin DE1-SoC wrapper
  -> Quartus compile for Cyclone V
```

The goal is not to implement Snitch yet.  The goal is to answer one narrow
question first:

```text
Can Quartus consume a gate-level netlist produced by an external synthesis tool
when we provide a small compatibility wrapper around the generated cells?
```

## Inputs

The gate-level netlist in `rtl/toy_counter_genus_netlist.v` was produced in the
lab with Cadence Genus 21.18 using:

```bash
export LM_LICENSE_FILE=5280@license
export CDS_LIC_FILE=5280@license
/local/tools/GENUS2118/bin/genus -no_gui -legacy_ui -files genus_toy_with_lib.tcl
```

The public reproduction inputs are kept in `lab/`:

```text
lab/toy_counter.sv
lab/toy_counter_tb.sv
lab/genus_toy_with_lib.tcl
```

The Genus script used this TSMC65 Liberty file:

```text
/local/users/tsmc65/Base_PDK/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_200a/tcbn65lptc.lib
```

The mapped netlist was also simulated in Questa with the matching TSMC cell
model and passed:

```text
PASS count=3
Errors: 0, Warnings: 0
```

## Local Quartus Wrapper

The local wrapper in `rtl/de1_s16_gatelevel_import.v` connects the imported
counter to the DE1-SoC board:

```text
CLOCK_50  -> gate-level counter clock
KEY[0]    -> active-low reset
SW[0]     -> enable
LEDR[7:0] -> counter value
LEDR[8]   -> enable mirror
LEDR[9]   -> reset mirror
```

The file `rtl/tcbn65lp_toy_shims.v` is intentionally not the vendor cell
library.  It is a tiny compatibility shim for only the seven cell names used by
this toy netlist.  This avoids committing proprietary TSMC model files while
still testing whether Quartus accepts the external mapped structure.

## Run

```bash
cd fpga/de1-soc/x0_gatelevel_quartus_import
./scripts/build.sh
```

## Observed Result

This probe was compiled on 2026-07-09 and programmed on 2026-07-10 with Quartus
Prime Lite 25.1 for the DE1-SoC Cyclone V device `5CSEMA5F31C6`.

Quartus accepted the imported Genus netlist and the compatibility shims:

```text
Quartus Prime Analysis & Synthesis was successful. 0 errors, 0 warnings.
Quartus Prime Fitter was successful. 0 errors, 2 warnings.
Quartus Prime Assembler was successful. 0 errors, 0 warnings.
Quartus Prime Timing Analyzer was successful. 0 errors, 0 warnings.
Quartus Prime Full Compilation was successful. 0 errors, 2 warnings.
```

The important frontend evidence is that Quartus elaborated the Genus cell
instances:

```text
SDFCNQD1
MOAI22D0
OA21D0
CKND2D0
IAO21D0
CKAN2D1
CKND0
```

The design used only 9 logic cells after Quartus remapping.  The first compile
was performed without JTAG hardware connected.  With the board connected on
2026-07-10, Quartus detected:

```text
1) DE-SoC [1-2]
```

The DE1-SoC JTAG chain exposes the ARM HPS debug endpoint at index 1 and the
Cyclone V FPGA at index 2.  An initial operation without an index selected the
HPS and failed with an ID mismatch.  `scripts/program.sh` therefore targets the
FPGA explicitly with:

```bash
quartus_pgm -m JTAG -o "p;output_files/de1_s16_gatelevel_import.sof@2"
```

Programming then passed:

```text
Using programming cable "DE-SoC [1-2]"
Device 2 contains JTAG ID code 0x02D120DD
Configuration succeeded -- 1 device(s) configured
Quartus Prime Programmer was successful. 0 errors, 0 warnings
```

The expected `SW[0]`, `KEY[0]`, and LED behavior was then physically confirmed
on the board.  X0 is therefore complete from Genus synthesis through physical
Cyclone V execution.

The reconstructed local netlist and the server-generated netlist have different
whole-file hashes because their provenance comments differ.  After removing
comments and blank lines, both produce this SHA-256 hash, confirming that their
Verilog logic is identical:

```text
d34fbfd5c87bc2438e0708dbdad20f89bb25ce7240a15f0dc771761312c7a3cf
```

See `captures/s16_quartus_compile_2026-07-09.txt` and
`captures/s16_jtag_program_2026-07-10.txt` for the compact result logs.

Build and program the generated `.sof` with:

```bash
./scripts/program.sh
```

## Interpretation

If Quartus accepts this design, it proves only this:

```text
External gate-level netlist + simple compatibility shims + thin DE1 wrapper
can compile for Cyclone V and configure the physical DE1-SoC FPGA.
```

It does not prove that a Snitch netlist will fit or behave correctly.  For
Snitch, the hard parts are larger:

```text
many more generated cells
memories/macros
clocking and reset assumptions
possible ASIC-only or Xilinx-only primitives
debug visibility loss after synthesis
timing/resource mapping on Cyclone V
```

The next escalation after this toy probe is a slightly larger module, not the
full Snitch cluster.
