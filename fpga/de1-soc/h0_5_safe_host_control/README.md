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
│ 0x08   │ STATUS       │ R      │ held, released, PLL, fetch, result │
│ 0x0c   │ CLUSTER_BASE │ R      │ 0x00001000                         │
│ 0x10   │ BOOT_RESULT  │ R      │ H0.7 data-path signature           │
└────────┴──────────────┴────────┴────────────────────────────────────┘
```

`CONTROL.bit0` resets to zero. Writes affect it only when byte lane zero is
enabled. Local accesses complete without asserting any forwarded transaction.

`STATUS` uses bit 0 for reset held, bit 1 for reset released, bit 2 for PLL
lock, bit 3 for the H0.6 boot-ROM fetch observation, and bit 4 for the H0.7
result observation. Observation bits remain set while the cluster runs, then
clear when cluster reset is reasserted.

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
operation. It fails unless `CONTROL=0` and `STATUS` reports reset held. It uses
raw ARM Linux syscalls and is statically linked without libc, so it also runs
on the older Ubuntu 16.04 userspace supplied by the Terasic LXDE image.

## Board Result

Verified on the DE1-SoC LXDE image on 2026-07-12. The display/framebuffer path
was stopped before JTAG programming so Linux remained responsive while the
fabric changed. The static probe was transferred over UART and run with `sudo`
because `/dev/mem` is root-only:

```text
ID           = 0x48300005
CONTROL      = 0x00000000
STATUS       = 0x00000005
CLUSTER_BASE = 0x00001000
H0.5_READ_ONLY_PASS
TEST_RC=0
```

`STATUS=0x5` proves that the PLL is locked and the cluster remains held in
reset. This test read only the local control page; it neither released reset
nor accessed the forwarded cluster window.
