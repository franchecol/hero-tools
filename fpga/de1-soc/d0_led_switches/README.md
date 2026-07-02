# DE1-SoC D0 LED/Switch Smoke Test

This is the first FPGA-only bring-up test for the DE1-SoC board.

It does not use the ARM/HPS side, Linux, the microSD card, Snitch, or Occamy.
It only proves that this path works:

```text
Linux PC -> Quartus -> USB-Blaster/JTAG -> Cyclone V FPGA fabric -> red LEDs
```

## Behavior

The FPGA mirrors the ten slide switches to the ten red LEDs:

```text
SW[0] -> LEDR[0]
SW[1] -> LEDR[1]
...
SW[9] -> LEDR[9]
```

If the bitstream is programmed correctly, moving a switch changes the matching
red LED.

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d0_led_switches
./scripts/build.sh
```

The output bitstream is:

```text
de1_d0_led_switches.sof
```

## Program

Connect the DE1-SoC USB-Blaster cable and run:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d0_led_switches
./scripts/program.sh
```

This programs the FPGA SRAM only. The design disappears after board reset or
power cycle, which is what we want for a safe smoke test.

## Manual GUI Flow

To recreate the same project using only the Quartus GUI, see:

```text
GUI_TUTORIAL.md
```
