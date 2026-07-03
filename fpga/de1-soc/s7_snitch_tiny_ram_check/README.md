# Snitch-Lite S7: Tiny RAM Check

S7 extends S6 from "Snitch can write MMIO" to "Snitch can store to local data
RAM, load the value back, check it, and report pass/fail through MMIO LEDs."

This is still intentionally tiny. It is not a full Snitch cluster and it does
not use HPS/Linux yet.

## Flow

```text
sw/ram_check.S
      │
      ▼
riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e
      │
      ▼
generated/sw/payload.elf
      │
      ├── generated/sw/payload.dump
      ├── generated/sw/payload.nm
      ▼
generated/sw/payload.bin
      │
      ▼
scripts/bin_to_rom_svh.py --max-words 64
      │
      ├── generated/rom_words.svh
      ├── generated/rom_manifest.json
      ▼
Snitch instruction ROM
      │
      ▼
Snitch store/load tiny RAM at 0x00001000
      │
      ▼
Snitch writes pass/fail to LED MMIO at 0x40000000
```

## Memory Map

```text
0x00000000  instruction ROM, generated from sw/ram_check.S
0x00001000  tiny local data RAM, 16 words
0x40000000  LED MMIO register
```

## Software Behavior

The default payload does this:

```text
store 0x000000a5 to 0x00001000
load  from       0x00001000
if loaded value == 0x000000a5:
    write 0x000001a5 to LED MMIO
else:
    write 0x0000005a to LED MMIO
park forever
```

## LED Meaning

```text
LEDR[7:0] = result byte written by Snitch
LEDR[8]   = RAM check passed
LEDR[9]   = reset is released
```

Expected board pattern after programming and releasing reset:

```text
LEDR[7:0] = 0xa5
LEDR[8]   = 1
LEDR[9]   = 1
```

If the check fails, the low LEDs show:

```text
LEDR[7:0] = 0x5a
LEDR[8]   = 0
LEDR[9]   = 1
```

## Run

Build only the software ROM artifacts:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s7_snitch_tiny_ram_check
./scripts/build_sw_rom.sh
```

Translation and structural check:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s7_snitch_tiny_ram_check
./scripts/run_sv2v_probe.sh
```

Quartus analysis/elaboration:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s7_snitch_tiny_ram_check
./scripts/quartus_preflight.sh
```

Full Quartus compile:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s7_snitch_tiny_ram_check
./scripts/build.sh
```

Program the board:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s7_snitch_tiny_ram_check
./scripts/program.sh
```

After programming, press and release `KEY0` once. `KEY0` is the active-low
reset input for this design.

## Verified Result

This stage was checked on the local DE1-SoC setup:

```text
software ROM build:              PASS
oversized ROM negative test:     PASS
sv2v translation:                PASS
Yosys structural probe:          PASS
Quartus analysis/elaboration:    PASS
Quartus full compile:            PASS
Quartus JTAG programming:        PASS
physical LED observation:        pending user confirmation
```

Quartus full compile summary:

```text
device:              5CSEMA5F31C6
ALMs:                709 / 32,070 (2%)
registers:           915
pins:                15 / 457 (3%)
block memory bits:   0 / 4,065,280 (0%)
DSP blocks:          0 / 87 (0%)
worst setup slack:   2.890 ns
worst hold slack:    0.175 ns
compile result:      0 errors, 76 warnings
```

The generated ROM manifest for the default payload reports:

```text
ROM words: 14 / 64
ROM bytes: 56
SHA-256:   e851776fd1a5def8a207537de6b884e429fd13d65e4736acb127bd61fbaa3ad4
```

The programmed bitstream targets device index 2 in the DE1-SoC JTAG chain:

```text
5CSEMA5F31@2
```

## What This Proves

If the build and board test pass, S7 proves:

```text
Snitch fetches a generated ROM program.
Snitch can issue a data store to a tiny FPGA RAM.
Snitch can issue a data load from that RAM.
Snitch can branch on the loaded result.
Snitch can report pass/fail through board-visible MMIO.
```

## What This Still Does Not Prove

```text
Not a full Snitch cluster.
No TCDM.
No DMA.
No host/HPS Linux integration.
No external runtime loader yet.
No writable program memory yet.
```

After S7, the next likely step is S8: add a minimal host-visible control/status
interface so the ARM/HPS side can eventually start or observe the Snitch-Lite
FPGA block.
