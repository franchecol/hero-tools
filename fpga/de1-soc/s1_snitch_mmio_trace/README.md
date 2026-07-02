# Snitch-Lite S1: Simulated MMIO Store

S1 continues the real-Snitch path without using the DE1-SoC ARM/Linux side.

S0 proved that a reduced real Snitch target can boot and run a tiny bare-metal
program in Verilator. S1 adds the next missing piece: a peripheral-style store.

## What This Proves

```text
real Snitch RTL boots
real Snitch executes a bare-metal ELF
real Snitch issues a store to fake MMIO address 0x4000_0000
the trace checker verifies the expected address and value
```

The fake MMIO address is:

```text
0x4000_0000
```

The expected value is:

```text
0x0badcafe
```

This is not an FPGA LED register yet. It is the simulator-side proof that the
Snitch core can execute the software pattern that will later become:

```text
Snitch store -> MMIO register -> LED/UART/Avalon peripheral
```

## Flow

```text
cfg/one-core.hjson
  -> Snitch cluster generator
  -> generated RTL and software headers
  -> mmio.elf
  -> Verilator Snitch testbench
  -> trace_hart_00000.dasm
  -> check_mmio_trace.py
```

## Build The MMIO Software Test

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s1_snitch_mmio_trace
./scripts/build_sw_mmio.sh
```

This builds:

```text
sw/mmio.S
```

The program intentionally avoids `snRuntime`, DMA setup, OpenMP, libc, and
custom Snitch instructions. It only performs normal RV32 instructions.

## Build The Verilator Simulator

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s1_snitch_mmio_trace
./scripts/build_sim.sh
```

This reuses the same reduced one-core Snitch configuration as S0.

## Run And Check

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s1_snitch_mmio_trace
./scripts/run_mmio.sh
```

The run is considered passing when it ends with:

```text
S1 MMIO trace check passed
```

## Verified Result

This sequence has been verified on the local machine:

```bash
./scripts/build_sw_mmio.sh
./scripts/build_sim.sh
./scripts/run_mmio.sh
```

The checker found:

```text
found expected MMIO store: line=11 addr=0x40000000 value=0x0badcafe
S1 MMIO trace check passed
```

## Why This Comes Before Quartus

S1 is still easier to debug than FPGA synthesis. If Snitch cannot issue a clean
MMIO-style store in Verilator, connecting that store to DE1-SoC LED/UART logic
would be premature.

After S1 passes, the next steps are:

```text
S2: create a small Quartus-facing wrapper around the reduced Snitch target
S3: connect the MMIO-style store path to board-visible LED/UART/register logic
```
