# H0.1: Stable Upstream Cluster Shell

H0.1 is the first heterogeneous-integration boundary. It wraps the
Genus-translated upstream cluster with semantic AXI signal names and exposes
only its 64-bit `narrow_in` AXI slave to the future ARM/HPS adapter.

```text
ARM/HPS and Avalon adapter (H0.2)
                 │
                 ▼
       stable 64-bit AXI host port
                 │
                 ▼
      original upstream Snitch cluster
```

Unused external AXI directions are tied off with explicit error/no-response
values. This is safe for the current cluster configuration because U3 disabled
DMA and the generated one-core test does not require external memory during
the shell elaboration test.

## Reuse From Snitch-Lite

```text
Reusable unchanged or nearly unchanged
────────────────────────────────────────────────────────────
SL9 HPS lightweight bridge configuration
Platform Designer clock/reset bridges
Qsys generation and bridge-only HPS mode
Quartus programming and RBF conversion scripts
ARM Linux /dev/mem and serial-transfer infrastructure

Must be replaced for upstream Snitch
────────────────────────────────────────────────────────────
SL9 custom Avalon register block
Snitch-Lite ROM/RAM loader protocol
Snitch-Lite start/done register semantics
Snitch-Lite accelerator-internal address map
```

## Gate

H0.1 passes when Quartus can elaborate and synthesize this stable shell at a
20 MHz constraint while retaining the SRAM-correct cluster:

```bash
./scripts/build.sh
```

H0.2 will implement the Avalon-to-AXI transaction adapter and package this
shell as a Platform Designer component connected to the proven SL9 HPS bridge.

## Result

The first Quartus Analysis & Synthesis run passes:

```text
Stable semantic AXI shell: PASS
20 MHz constraint:         applied
Registers:                 6,356
Block-memory bits:         169,728
```

The lower register count than U5.2 is expected because H0.1 deliberately ties
off unused outbound interfaces and Quartus can remove logic that has no
observable effect. H0.1 is an interface/elaboration gate, not a replacement
for U5.2's complete-cluster capacity result.
