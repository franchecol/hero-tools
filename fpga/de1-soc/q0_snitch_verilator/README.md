# Q0: Upstream Snitch Verilator Baseline

Q0 starts the real-Snitch path without using the DE1-SoC ARM/Linux side.

It uses:

```text
real Snitch RTL source
  from platforms/occamy/.bender/git/checkouts/snitch_cluster-*/

real Snitch LLVM toolchain
  from install/bin/riscv32-unknown-elf-clang

one-core educational config
  from cfg/one-core.hjson
```

The goal is not FPGA synthesis yet. The goal is to prove that a reduced real
Snitch target can build and run a tiny bare-metal program in Verilator.

## Flow

```text
cfg/one-core.hjson
  -> Snitch cluster generator
  -> generated RTL and software headers
  -> minimal.elf
  -> Verilator Snitch testbench
```

## Build The Minimal Bare-Metal Test

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/q0_snitch_verilator
./scripts/build_sw_baremetal.sh
```

This builds:

```text
sw/minimal.S
```

This file avoids `snRuntime`, DMA setup, OpenMP, libc, and custom Snitch
instructions. It only checks that the generated Snitch RTL can fetch and run a
normal tiny RISC-V program.

## Build The Verilator Simulator

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/q0_snitch_verilator
./scripts/build_sim.sh
```

This may take substantially longer than the software build.

## Run The Test

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/q0_snitch_verilator
./scripts/run_baremetal.sh
```

Expected meaning if it passes:

```text
real Snitch RTL fetched instructions
real Snitch RTL ran a RISC-V bare-metal ELF
the test returned exit code 0 through the Snitch testbench
```

## Verified Result

This sequence has been verified on the local machine:

```bash
./scripts/build_sw_baremetal.sh
./scripts/build_sim.sh
./scripts/run_baremetal.sh
```

The run is considered passing when it ends with:

```text
Q0 bare-metal Snitch simulation passed
```

The trace confirms:

```text
boot ROM jumps to _start at 0x80000000
minimal.S writes 0x1235 to result
minimal.S writes 1 to tohost
FESVR exits with code 0
```

## Optional Upstream Runtime Test

The upstream `simple.c` test can also be built:

```bash
./scripts/build_sw_simple.sh
./scripts/run_simple.sh
```

That path links `snRuntime`. On this reduced one-core config it can fail before
`main()` if the runtime emits Snitch-specific DMA/helper instructions that the
tiny config does not implement yet. That is useful later, but it is not the Q0
pass criterion.

## Why This Comes Before Quartus

Quartus is slower and harder to debug. If the one-core Snitch config does not
run in Verilator first, putting it on DE1-SoC is premature.

After Q0 passes, the next steps are:

```text
Q1: add a tiny MMIO location to the simulated Snitch system
Q2: make the bare-metal program write that MMIO location
SL3: port the reduced Snitch system wrapper to Quartus
SL4: connect that MMIO location to LEDR/HEX/UART on DE1-SoC
```
