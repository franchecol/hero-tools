# Snitch-Lite S4: ROM To MMIO LED

S4 is the first DE1-SoC stage where the real upstream Snitch core is connected
to a tiny instruction source and a board-visible MMIO register.

S3 proved:

```text
real snitch.sv core subset -> sv2v -> Yosys -> Quartus -> .sof
```

S4 asks the next question:

```text
Can Snitch fetch real instructions and issue a store that changes LEDR?
```

## Hardware Shape

```text
CLOCK_50 / KEY[0]
      |
      v
real upstream snitch.sv core
      |
      +-- instruction ROM, combinational, 4 words
      |
      +-- tiny data responder
            |
            +-- MMIO LED register at 0x40000000
```

The ROM program is:

```text
0x00000000: 400002b7  lui  t0, 0x40000
0x00000004: 15500313  addi t1, zero, 0x155
0x00000008: 0062a023  sw   t1, 0(t0)
0x0000000c: 0000006f  j    0x0000000c
```

The assembly documentation copy is:

```text
sw/led_mmio.S
```

## LED Meaning

```text
LEDR[7:0] = low 8 bits written by Snitch to MMIO
LEDR[8]   = Snitch MMIO write was observed
LEDR[9]   = reset is released
```

Expected board pattern after programming and releasing reset:

```text
LEDR[7:0] = 0x55
LEDR[8]   = 1
LEDR[9]   = 1
```

## Run

Translation and structural check:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s4_snitch_rom_mmio_led
./scripts/run_sv2v_probe.sh
```

Quartus analysis/elaboration:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s4_snitch_rom_mmio_led
./scripts/quartus_preflight.sh
```

Full Quartus compile:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s4_snitch_rom_mmio_led
./scripts/build.sh
```

Program the board:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s4_snitch_rom_mmio_led
./scripts/program.sh
```

After programming, press and release `KEY0` once. `KEY0` is the active-low
reset input for this design.

Generated files are ignored by git and written under:

```text
generated/
```

## What This Proves

If the build and board test pass, S4 proves:

```text
Quartus can compile a real Snitch-core shell.
Snitch can fetch a tiny instruction stream.
Snitch can execute normal RV32E instructions.
Snitch can issue a data-store transaction.
The local MMIO shell can convert that store into board-visible LED state.
```

## Verified Result

Verified locally on 2026-07-02 with Quartus Prime Lite 25.1std.0:

```text
sv2v:
  PASS

Yosys:
  PASS

Quartus analysis/elaboration:
  PASS

Quartus full compile:
  PASS
  SOF:
    generated/output_files/de1_s4_snitch_rom_mmio_led.sof

Quartus programmer:
  PASS
  Device 5CSEMA5F31@2 configured over JTAG.
```

Quartus summary:

```text
Device:                  5CSEMA5F31C6
Logic utilization:       127 / 32,070 ALMs (< 1 %)
Registers:               117
Block memory bits:       0
DSP blocks:              0
Worst setup slack:       9.975 ns on CLOCK_50
Worst hold slack:        0.114 ns on CLOCK_50
Full compile status:     0 errors, 74 warnings
```

The resource number is still not a full Snitch-core utilization number. The ROM
program is tiny, optional features are disabled, and Quartus can still optimize
unused behavior. It is stronger than S3 because the LED value now depends on a
Snitch-issued data-store transaction.

## What This Still Does Not Prove

```text
Not a full Snitch cluster.
No TCDM.
No DMA.
No host/HPS Linux integration.
No external software image loading.
No realistic memory system yet.
```

After S4, the next useful stage is to replace the hardcoded ROM with a build
step that compiles assembly into ROM contents.
