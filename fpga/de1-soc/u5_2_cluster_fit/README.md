# U5.2: SRAM-Correct Complete-Cluster Fit

U5.2 runs the complete Quartus flow on the upstream cluster after U5.1
preserved all eight SRAM banks as Cyclone V M10K-backed `altsyncram`
instances. It answers whether the complete imported configuration can be
placed, routed, assembled, and timed on the DE1-SoC device.

```text
U4 Genus structural cluster
            │
            ▼
U5.1 explicit Cyclone SRAM boundary
            │
            ▼
Quartus map -> fit -> assembler -> timing analyzer
```

The flattened host-facing ports are virtual because this experiment measures
the cluster before adding an HPS/board wrapper. `clk_i` remains a real clock
port constrained to 50 MHz.

## Run

```bash
./scripts/build.sh
```

The ignored U4 Genus netlist must exist locally. Physical fit and 50 MHz timing
are separate gates: a routed design can pass fit while failing the requested
clock period.

## Result

The first verified full compile completed successfully through the Assembler
and Timing Analyzer:

```text
Physical Fitter:       PASS
Logic utilization:    12,029 / 32,070 ALMs (38%)
Registers:             7,035
Block-memory bits:     169,728 / 4,065,280 (4%)
Physical RAM blocks:   24 / 397 M10Ks (6%)
DSP blocks:            0 / 87
Configuration output: cluster_fit.sof generated

50 MHz setup timing:   FAIL
Worst setup slack:     -21.477 ns
Worst hold slack:      +0.148 ns
Worst-corner Fmax:      24.11 MHz
```

The complete SRAM-correct imported cluster therefore fits comfortably in
device capacity. It can begin at a conservative clock such as 20 MHz, but it
cannot be considered a 50 MHz implementation without further timing work.

This result changes the next decision. Feature reduction is not required for
capacity. The next milestone should create the actual DE1/HPS wrapper and use
a safe divided clock, while keeping timing closure toward 50 MHz as a separate
optimization track.
