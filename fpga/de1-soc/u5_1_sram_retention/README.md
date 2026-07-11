# U5.1: Full-Cluster SRAM Retention

U5.1 establishes a trustworthy memory baseline before reducing the upstream
cluster. U4 proved that inferred Cyclone SRAMs work in isolation, but Quartus
retained zero M10Ks in the complete imported hierarchy. U5.1 replaces that
heuristic inference boundary with Intel's explicit `altsyncram` primitive.

```text
Genus structural cluster
        │
        ├── 4 x 512 x 64 TCDM
        ├── 2 x 128 x 128 I-cache data
        └── 2 x 128 x 24 I-cache tag
                    │
                    ▼
            explicit altsyncram
                    │
                    ▼
              Cyclone V M10Ks
```

The implementation remains behind the upstream `tc_sram_impl` technology-cell
boundary. It does not change the Snitch core, TCDM interconnect, cache logic,
addresses, data widths, byte enables, or one-cycle synchronous read contract.

## Gate

The experiment passes only when Quartus Analysis & Synthesis completes, its
report contains eight retained `altsyncram` instances, and it reports 169,728
physical block-memory bits. A fit is intentionally not required yet because
U4 already established that the unreduced cluster is too large.

The upstream interfaces expose 169,984 logical bits. Quartus removes bit 22
from both 128-word I-cache tag banks because that bit is unused by the imported
cluster, accounting exactly for the 256-bit difference:

```text
169,984 logical bits - 2 banks x 128 unused bits = 169,728 retained bits
```

```bash
./scripts/build.sh
```

The ignored U4 Genus netlist must still exist locally at:

```text
../u4_cyclone_memory_boundary/generated/de1_u4_cluster_generic.v
```

After this gate passes, U5.2 can compare trustworthy resource usage by
hierarchy and begin the reduced-upstream configuration sweep.

## Result

U5.1 passes with Quartus Prime Lite 25.1:

```text
Analysis & Synthesis:       successful
Retained SRAM banks:        8
Retained block-memory bits: 169,728
Registers:                  6,854
Estimated ALMs:             13,138 / 32,070 (41%)
```

This corrects U4's misleading `176,883` registers and `129,784` estimated
ALMs. The new estimate is below device capacity, but Analysis & Synthesis is
not proof of fit. U5.2 must run the Fitter and measure physical M10K use,
placement, routing, and timing before deciding whether feature reduction is
necessary.
