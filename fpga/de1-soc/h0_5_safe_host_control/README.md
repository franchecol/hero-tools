# H0.5: Safe HPS Host Control

H0.5 adds the control-plane boundary required before programming the H0.3
cluster bitstream on the board. The cluster is held in reset after FPGA/system
reset, while Linux can safely identify the block without touching cluster AXI.

```text
HPS lightweight bridge
          │
          ▼
safe_host_control
  ├── 0x0000-0x0fff local control/status
  └── 0x1000+        forwarded cluster window
```

## Register Map

Offsets are bytes from the HPS lightweight bridge base:

```text
┌────────┬──────────────┬────────┬────────────────────────────────────┐
│ Offset │ Name         │ Access │ Meaning                            │
├────────┼──────────────┼────────┼────────────────────────────────────┤
│ 0x00   │ ID           │ R      │ 0x48300005                         │
│ 0x04   │ CONTROL      │ R/W    │ bit0=release cluster reset         │
│ 0x08   │ STATUS       │ R      │ bit0=held, bit1=released, bit2=PLL │
│ 0x0c   │ CLUSTER_BASE │ R      │ 0x00001000                         │
└────────┴──────────────┴────────┴────────────────────────────────────┘
```

`CONTROL.bit0` resets to zero. Writes affect it only when byte lane zero is
enabled. Local accesses complete without asserting any forwarded transaction.

## Test

```bash
./scripts/test_control.sh
```

The simulation checks reset safety, local register reads, byte-enable handling,
address-window rebasing, and forwarded Avalon wait/data/control signals.

## Physical Result

The safe router is integrated ahead of H0.2 in a generated Qsys system and a
complete DE1 project:

```text
Control simulation:      PASS
Qsys generation:         PASS, 21 modules / 82 files
Quartus map/fit:          PASS
Logic utilization:       9,674 / 32,070 ALMs (30%)
Registers:               7,397
M10K blocks:             24 / 397 (6%)
Worst setup slack:       +19.479 ns
Worst hold slack:        +0.125 ns
Combinational loops:     0
SOF and RBF:             generated
```

## Execution Gate

This physical pass is intentionally not an execution pass. The synthesized
upstream configuration has:

```text
Snitch BootAddr:       0x00001000
Cluster TCDM base:     0x10000000
External fetch path:   currently tied to an AXI error response
```

Releasing cluster reset would therefore request instructions from an
unimplemented external boot-memory path. The next board test may read only the
local H0.5 registers while reset remains held. H0.6 must resolve boot memory,
either by resynthesizing with a TCDM boot address or by implementing the
external boot target, before execution is enabled.

Build the ARM read-only probe with:

```bash
./scripts/build_arm_probe.sh
```

The program opens `/dev/mem` read-only and does not contain a register-write
operation. It fails unless `CONTROL=0` and `STATUS` reports reset held. The
local cross-toolchain lacks its static atomic support archive, so this probe is
dynamically linked and requires `/lib/ld-linux-armhf.so.3`, provided by the
current Terasic LXDE image.
