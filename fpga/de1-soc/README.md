# DE1-SoC FPGA Bring-Up

This directory tracks the educational DE1-SoC path toward a tiny accelerator.

It is intentionally separate from the full Occamy FPGA path. The DE1-SoC board
is useful for small staged hardware experiments, not for full Occamy.

## Stages

```text
D0: LED/switch smoke test
    Proves Quartus, USB-Blaster/JTAG, FPGA programming, switches, and LEDs.

D1: register accelerator smoke test
    Adds clocked state, operand registers, opcode selection, result, busy, done,
    and 7-segment output.

D2: JTAG/PC to FPGA MMIO register access
    Replace manual buttons/switches with real Avalon-MM register writes using
    System Console over USB-Blaster/JTAG. The same register block is intended
    for the later HPS lightweight bridge.

D3: HPS/ARM Linux to FPGA MMIO register access
    Connect the same D2 register block to the HPS lightweight bridge and access
    it from ARM Linux.
```

## Current Projects

```text
d0_led_switches/
  SW[9:0] -> LEDR[9:0]

d1_register_accel/
  KEY/SW-controlled mini accelerator:
  A register, B register, opcode, busy, done, result

d2_jtag_mmio_accel/
  System Console/JTAG-controlled mini accelerator:
  Avalon-MM register block, ID/status/control/data/result registers

s0_snitch_verilator/
  Real-Snitch simulation path:
  one-core Snitch config, tiny bare-metal ELF, Verilator testbench

s1_snitch_mmio_trace/
  Real-Snitch simulated MMIO path:
  one-core Snitch config, fake MMIO store, trace-checked result

s2_snitch_quartus_wrapper/
  Quartus-facing Snitch wrapper path:
  one-core Snitch config, Bender-to-QSF export, analysis/elaboration preflight.
  Current result: export works; Quartus Lite reaches Snitch RTL and then stops
  on unsupported advanced SystemVerilog syntax.
```

Manual GUI scratch projects should use a `*_gui_manual/` directory name. Those
directories are ignored because they contain generated Quartus build outputs.

## Snitch-Lite Track

The `D*` projects are DE1-SoC FPGA board bring-up projects. The `S*` projects
are the path toward a real Snitch core/cluster.

```text
S0: Verilator first
    Build a reduced real Snitch target and run a tiny bare-metal program.

S1: simulated MMIO
    Add a small MMIO register and make Snitch write it from software.
    Current S1 checks the MMIO-style store in the Verilator trace.

S2: Quartus wrapper
    Try to synthesize the reduced Snitch wrapper for the DE1-SoC FPGA.
    Current S2 first exports a Quartus project and runs analysis/elaboration.
    Verified status: project export passes; Quartus Lite analysis does not yet
    pass because real Snitch dependencies use advanced SystemVerilog features.

S3: board-visible MMIO
    Connect the Snitch-written register to LEDR/HEX/UART.
```
