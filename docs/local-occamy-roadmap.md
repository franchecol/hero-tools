# Local Occamy Milestone Roadmap

This page is the authoritative index for the reduced Occamy work on the
`occamy-minimal-bootstrap` branch. Start here when you want to understand the
incremental progression, reproduce one milestone, find detailed evidence, or
continue to FPGA.

## Progress At A Glance

```text
┌─────┬──────────────────────────────────────────────┬───────────┐
│ M0  │ CVA6 wakes Snitch and receives completion   │ completed │
│ M1  │ Snitch changes host-visible shared memory   │ completed │
│ M2  │ Runtime, DMA, barriers, FP AXPY              │ completed │
│ M3a │ Live mailbox manager calls a device target  │ completed │
│ M3b │ Linux/OpenMP launches replay via Verilator  │ frozen    │
│ M4  │ Real FPGA map(tofrom) proof                  │ next      │
└─────┴──────────────────────────────────────────────┴───────────┘
```

The progression deliberately increases one integration boundary at a time:

```text
M0 control
  └─▶ M1 shared data
       └─▶ M2 realistic device runtime
            └─▶ M3a mailbox target launch
                 └─▶ M3b Linux/OpenMP software integration
                      └─▶ M4 real FPGA endpoint
```

Status words mean:

```text
completed  deterministic milestone command and verification are available
frozen     accepted software baseline with explicit scope boundaries
next       defined continuation that still requires implementation or hardware
```

## M3 Naming

M3 has two explicit layers:

```text
M3a
  Deterministic live mailbox-runtime proof inside one Verilator simulation.
  It proves that the real Snitch-side mailbox manager receives a launch,
  calls omp_mailbox_target, writes the result, and returns completion.

M3b
  Broader HeroSDK/OpenMP software freeze.
  A qemu Linux host reaches the Occamy plugin, captured launches replay through
  Verilator, and replay-derived copybacks let the benchmark complete.
```

M3a is a prerequisite and focused diagnostic. M3b is the broader frozen
software result. Neither is a continuously connected Linux-to-Verilator device
model, which is why M4 moves to the real FPGA path.

## Reproduce A Milestone

### M0: Minimal Control Path

Purpose:

```text
CVA6 starts a Snitch payload.
Snitch raises the host software interrupt.
CVA6 observes completion and exits.
```

Canonical command:

```bash
./scripts/bootstrap-local-occamy-minimal.sh
```

Read:

- [M0 Manual Replay](local-occamy-m0-manual-replay.md) to reproduce every phase manually.
- [M0 Bootstrap And Runner](local-occamy-m0-bootstrap-runner.md) to understand the automation.
- [M0 Deep Dive](local-occamy-m0-deep-dive.md) for architecture, registers, traces, waveforms, and debugging history.

### M1: Shared-Memory Roundtrip

Purpose:

```text
The host initializes 16 words and passes their address.
Snitch increments every word.
The host validates every returned value.
```

Canonical command:

```bash
./scripts/bootstrap-local-occamy-m1.sh
```

Read [M1 Manual Replay](local-occamy-m1-manual-replay.md).

### M2: Runtime And Numerical Kernel

Purpose:

```text
Build a realistic RV32 payload through the HeroSDK LLVM path.
Exercise Snitch runtime startup, DMA, barriers, and floating point.
Numerically verify all 24 AXPY outputs.
```

Canonical command:

```bash
./scripts/bootstrap-local-occamy-m2.sh
```

Read [M2 Manual Replay](local-occamy-m2-manual-replay.md).

### M3a: Live Mailbox Runtime

Purpose:

```text
The host sends START, a device function address, and an argument pointer.
The real Snitch mailbox manager calls omp_mailbox_target.
The target changes 0x12345678 to 0x12345679.
The device returns completion code 0x04.
```

Canonical command:

```bash
./scripts/bootstrap-local-occamy-m3.sh
```

Read [M3a Manual Replay](local-occamy-m3-manual-replay.md).

### M3b: Full OpenMP Replay Freeze

Purpose:

```text
Build the HeroSDK/OpenMP cva6/occamy software stack.
Reach the Occamy plugin from qemu-riscv64.
Replay all 16 captured launches through the real Snitch mailbox manager.
Return the five observed map(tofrom) W32 copybacks.
```

Canonical frozen run:

```bash
./scripts/run-local-occamy-openmp-replay-bridge.sh --all
```

Read [M3b OpenMP Replay Freeze](local-occamy-m3b-openmp-freeze.md) for setup,
evidence, artifacts, caveats, and lower-level debug commands.

### M4: Real FPGA Bring-Up

Purpose:

```text
Replace fake/replay endpoints with the real board, driver, memory mappings,
mailboxes, interrupts, and host/device copyback.
```

First application:

```text
apps/omp/basic/map_tofrom_u32
```

First success criterion:

```text
PASS map_tofrom_u32: tmp_1=10 tmp_2=10
```

M4 requires the VCU128-oriented FPGA environment and cannot be completed with
the local Verilator setup alone. Read the
[M4 FPGA Bring-Up Plan](local-occamy-m4-fpga-bringup.md).

## Choose A Document

```text
I want the overall progression
  └─▶ this roadmap

I want to reproduce one milestone manually
  ├─▶ M0 Manual Replay
  ├─▶ M1 Manual Replay
  ├─▶ M2 Manual Replay
  └─▶ M3a Manual Replay

I want to understand the automation
  └─▶ M0 Bootstrap And Runner

I want architecture and debugging depth
  └─▶ M0 Deep Dive

I want to compare standalone Snitch with Occamy
  └─▶ Device-Side Snitch Comparison

I want the complete Linux/OpenMP replay evidence
  └─▶ M3b OpenMP Replay Freeze

I want to continue on real hardware
  └─▶ M4 FPGA Bring-Up Plan
```

## Scope Boundary

The completed software work proves:

```text
reduced Occamy generation and Verilator execution
CVA6-to-Snitch control and shared-memory paths
Snitch runtime, DMA, barriers, and floating-point execution
mailbox-managed target invocation
HeroSDK/OpenMP build and qemu plugin reachability
captured OpenMP launch replay through the real device mailbox manager
```

M4 still needs to prove:

```text
real FPGA bitstream, clocks, reset, and memory controller
real Linux driver endpoint and device-tree mappings
real MMIO, interrupts, and mailbox synchronization
real host/device memory visibility and map(tofrom) copyback
```

Simulation remains useful for debugging regressions, but the next integration
risk is the real platform endpoint rather than another larger software model.
