# H0.3: DE1 Upstream Cluster Physical Integration

H0.3 turns the generated H0.2 HPS/cluster system into a physical DE1-SoC
project. It generates a real Cyclone V PLL output at 15 MHz from `CLOCK_50`,
holds the system in reset until the PLL locks, and runs the complete Quartus
flow.

```text
DE1 CLOCK_50
      │
      ▼
Cyclone V PLL, 50 MHz -> 15 MHz
      │
      ├── HPS lightweight bridge clock
      ├── Avalon-to-AXI adapter clock
      └── upstream Snitch cluster clock
```

`LEDR[0]` reports PLL lock. `LEDR[1]` reports active system reset. `KEY[0]`
resets both the PLL and integrated system.

## Build

```bash
./scripts/build.sh
```

The build regenerates and retests every non-vendor boundary before Quartus:

```text
Verilator adapter test
Qsys HPS/cluster generation
Cyclone V PLL generation
Quartus map, fit, assembler, timing
SOF-to-RBF conversion
```

H0.3 passes only when the physical project fits, produces `.sof` and `.rbf`
artifacts, and meets timing on the generated 15 MHz cluster clock. The first
integrated 20 MHz fit missed worst-corner setup timing by 2.312 ns, so H0.3
uses a conservative clock instead of accepting a timing-invalid bitstream.

The verified 15 MHz build result is:

```text
Physical Fitter:       PASS
Logic utilization:     9,513 / 32,070 ALMs (30%)
Registers:             7,484
Block-memory bits:     169,728 / 4,065,280 (4%)
Physical RAM blocks:   24 / 397 M10Ks (6%)
PLL blocks:            1 / 6
Worst setup slack:     +9.466 ns
Worst hold slack:      +0.136 ns
Configuration output: .sof and .rbf generated
```

## Result Boundary

Physical fit and timing closure do not yet prove correct cluster execution.
Quartus reports a 244-node combinational loop in the imported Genus netlist.
The warning must be traced or eliminated before HPS software is allowed to
start the cluster. Until then, the H0.3 artifacts prove physical integration
and provide the basis for a non-destructive Linux MMIO probe only.

The HPS memory interfaces are intentionally omitted in this lightweight
bridge-only project, so Quartus also reports that the design is not fully
constrained. The generated 15 MHz cluster clock itself has positive setup and
hold slack at every analyzed corner.
