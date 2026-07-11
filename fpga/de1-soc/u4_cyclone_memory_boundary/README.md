# U4: Genus-to-Quartus Cluster Boundary

U4 converts U3's successful upstream-cluster synthesis proof into an FPGA-fit
experiment. It preserves the original Snitch cluster, TCDM interconnect,
I-cache, and `tc_sram_impl` interface while substituting only the memory
implementation behind that established technology-cell boundary.

```text
upstream cluster RTL ──► typed tc_sram_impl ──► Genus specialization
                                                  │
                                                  ▼
                                      fixed-width black-box cells
                                                  │
                                                  ▼
                                      Quartus M10K implementations
```

## Final result

```text
Gate                                                           Result
────────────────────────────────────────────────────────────────────────
1. Exact U3 memory geometries infer M10Ks in isolation          PASS
2. Genus preserves the three SRAM interfaces                   PASS
3. Quartus elaborates the translated upstream cluster          PASS
4. The cluster fits the DE1-SoC Cyclone V                      FAIL
5. Upstream software executes on this configuration            BLOCKED
```

The experiment proves the gate-level portability path proposed after U3:
Genus can consume the upstream SystemVerilog and emit structural Verilog that
Quartus Lite can elaborate. Quartus no longer fails on unsupported source RTL.
It reaches placement and rejects the design because it is too large.

```text
Quartus Analysis & Synthesis:  successful, 0 errors
Estimated ALMs after mapping:  129,784
Fitter ALMs required:          105,570 / 32,070 (329%)
Fitter LABs required:           12,053 / 3,207
Registers:                     176,883
Fitter result:                 cannot fit design in device
```

The complete reports are generated locally and intentionally ignored. The
small reviewable evidence is preserved in `results/`.

## Memory evidence

The standalone memory probe instantiates one of each exact U3 geometry:
`512 x 64` TCDM, `128 x 128` I-cache data, and `128 x 24` I-cache tag. It
drives every data bit and independently observes each read result so Quartus
cannot merge equivalent banks or prune constant lanes. Its purpose is
inference evidence, not a board demo.

That probe fits successfully at 50 MHz and reports:

```text
ALMs:                77 / 32,070
Registers:          160
Block-memory bits:  52,224 / 4,065,280
M10K blocks:         8 / 397
Worst setup slack:  +16.227 ns
Worst hold slack:    +0.109 ns
```

The 52,224 bits are exactly one instance of each geometry:

```text
512 x 64 + 128 x 128 + 128 x 24 = 52,224 bits
```

Quartus Lite cannot parse the upstream module's SystemVerilog `parameter type`
declarations. The Quartus side therefore uses fixed-width modules after Genus
has specialized those types; this is precisely why the gate-level boundary is
required rather than a source-level replacement.

## Full-cluster SRAM caveat

The full-cluster fit reports zero M10Ks and zero block-memory bits. This does
not mean the upstream cluster has no memories. Genus preserved one specialized
module for each required geometry, and the patched netlist instantiates four
`512 x 64` TCDM banks, two `128 x 128` I-cache data banks, and two `128 x 24`
I-cache tag banks. Quartus elaborated all three Cyclone wrapper types, but did
not retain any of those eight instances as physical RAM in the full top-level
result. The precise cause may be flattening, optimization, or an inference
contract lost at the structural-netlist boundary; this run does not prove
which one.

The expected logical storage represented by those banks is:

```text
4(512 x 64) + 2(128 x 128) + 2(128 x 24) = 169,984 bits
```

Consequently, `105,570 ALMs` is a valid proof that this imported netlist does
not fit, but it is not yet a trustworthy estimate of the optimally mapped
upstream cluster. Correct M10K retention should reduce ALM/register pressure;
it cannot make the present result a completed FPGA implementation without a
new successful fit.

## Decision and next experiment

Do not begin by randomly deleting cluster features from this netlist. First
make every expected SRAM bank survive the Genus/Quartus boundary and confirm
nonzero M10K use in the complete hierarchy. Then create a parameter sweep of
upstream configurations and record ALMs, registers, M10Ks, DSPs, and fit status.

The reduction order should preserve the real upstream Snitch core while
removing expensive surrounding features deliberately:

```text
1. Establish full-cluster SRAM-bank counts and M10K retention.
2. Measure logic by hierarchy to identify the dominant blocks.
3. Reduce TCDM size and banking.
4. Remove or reduce I-cache structures if configuration permits.
5. Disable DMA and unused AXI/peripheral paths.
6. Compare integer-only and reduced-FPU configurations.
7. Fit the smallest useful upstream configuration on Cyclone V.
```

This changes the next question from "does the original cluster fit?" (U4 has
answered no for this imported configuration) to "what is the largest genuine
upstream Snitch configuration that fits while retaining correct memories?"

## Reproduction

Generate the upstream wrapper and Genus source list locally:

```bash
./scripts/generate.sh
```

Run `lab/run_genus_boundary.tcl` with Genus in the licensed lab environment,
then transfer its generated generic netlist to:

```text
generated/de1_u4_cluster_generic.v
```

Prepare the Quartus-compatible netlist and run the two checks:

```bash
./scripts/build_memory_probe.sh
./scripts/build_cluster_fit.sh
```

The netlist injector replaces only the three SRAM technology boundaries,
shortens the oversized specialized cluster module name, and consistently
normalizes Genus escaped identifiers that crash the Quartus SGN frontend. It
does not intentionally alter connectivity or remove cluster functionality.
