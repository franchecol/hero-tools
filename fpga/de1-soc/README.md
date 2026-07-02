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
```

Manual GUI scratch projects should use a `*_gui_manual/` directory name. Those
directories are ignored because they contain generated Quartus build outputs.
