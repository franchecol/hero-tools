# Snitch-Lite S5: Generated Software ROM To MMIO LED

S5 keeps the S4 hardware behavior but removes the hardcoded instruction words
from the RTL.

The flow becomes:

```text
sw/led_mmio.S
      |
      v
riscv64-unknown-elf-gcc
      |
      v
generated/sw/led_mmio.elf
      |
      v
objcopy -O binary -j .text
      |
      v
generated/sw/led_mmio.bin
      |
      v
scripts/bin_to_rom_svh.py
      |
      v
generated/rom_words.svh
      |
      v
sv2v -> Yosys -> Quartus -> .sof
```

## Software Payload

The payload is normal RV32E assembly:

```text
sw/led_mmio.S
```

It performs:

```text
lui  t0, 0x40000       # t0 = 0x40000000
addi t1, zero, 0x155   # t1 = LED pattern
sw   t1, 0(t0)         # MMIO write to LED register
j    .
```

The verified generated ROM words are:

```text
0x00000000: 400002b7  lui  t0, 0x40000
0x00000004: 15500313  addi t1, zero, 0x155
0x00000008: 0062a023  sw   t1, 0(t0)
0x0000000c: 0000006f  j    0x0000000c
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

Build only the software ROM artifacts:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s5_snitch_generated_rom_mmio_led
./scripts/build_sw_rom.sh
```

Translation and structural check:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s5_snitch_generated_rom_mmio_led
./scripts/run_sv2v_probe.sh
```

Quartus analysis/elaboration:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s5_snitch_generated_rom_mmio_led
./scripts/quartus_preflight.sh
```

Full Quartus compile:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s5_snitch_generated_rom_mmio_led
./scripts/build.sh
```

Program the board:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s5_snitch_generated_rom_mmio_led
./scripts/program.sh
```

After programming, press and release `KEY0` once. `KEY0` is the active-low
reset input for this design.

## What This Proves

If the build and board test pass, S5 proves:

```text
The FPGA ROM contents come from a compiled software source file.
Snitch fetches the generated ROM instructions.
Snitch executes normal RV32E instructions.
Snitch issues a data-store transaction.
The local MMIO shell converts that store into board-visible LED state.
```

## Verified Result

Verified locally on 2026-07-02 with Quartus Prime Lite 25.1std.0:

```text
software ROM build:
  PASS
  generated/sw/led_mmio.elf
  generated/sw/led_mmio.bin
  generated/rom_words.svh

sv2v:
  PASS

Yosys:
  PASS

Quartus analysis/elaboration:
  PASS

Quartus full compile:
  PASS
  SOF:
    generated/output_files/de1_s5_snitch_generated_rom_mmio_led.sof

Quartus programmer:
  PASS
  Device 5CSEMA5F31@2 configured over JTAG.
```

Quartus summary:

```text
Device:                  5CSEMA5F31C6
Logic utilization:       102 / 32,070 ALMs (< 1 %)
Registers:               97
Block memory bits:       0
DSP blocks:              0
Worst setup slack:       9.572 ns on CLOCK_50
Worst hold slack:        0.175 ns on CLOCK_50
Full compile status:     0 errors, 74 warnings
```

## What This Still Does Not Prove

```text
Not a full Snitch cluster.
No TCDM.
No DMA.
No host/HPS Linux integration.
No external software loader yet.
No writable program memory yet.
```

After S5, the next useful step is to make the ROM generator more general:
support larger payloads and fail early if the program exceeds the chosen ROM
address range.
