# Snitch-Lite SL6: Checked Generated ROM

SL6 keeps the SL5 software-generated ROM behavior and makes the ROM generation
flow safer.

SL5 proved:

```text
assembly source -> ELF -> binary -> generated ROM -> Snitch MMIO LED write
```

SL6 adds checks around that path:

```text
maximum ROM size
4-byte alignment
non-empty binary
_start must link at 0x00000000
generated JSON manifest
generated ROM metadata comments
configurable assembly source path
```

## Flow

```text
sw/led_mmio.S
      |
      v
riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e
      |
      v
generated/sw/payload.elf
      |
      +--> generated/sw/payload.dump
      +--> generated/sw/payload.nm
      |
      v
objcopy -O binary -j .text
      |
      v
generated/sw/payload.bin
      |
      v
scripts/bin_to_rom_svh.py --max-words 64
      |
      +--> generated/rom_words.svh
      +--> generated/rom_manifest.json
      |
      v
sv2v -> Yosys -> Quartus -> .sof
```

## Changing The Program

Default payload:

```text
sw/led_mmio.S
```

Use a different assembly file:

```bash
S6_SW_SRC=/absolute/path/to/other.S ./scripts/build.sh
```

Change the ROM size limit:

```bash
S6_ROM_MAX_WORDS=128 ./scripts/build.sh
```

If the generated `.text` section exceeds the limit, the build fails before
`sv2v` or Quartus.

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
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl6_snitch_checked_rom_mmio_led
./scripts/build_sw_rom.sh
```

Translation and structural check:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl6_snitch_checked_rom_mmio_led
./scripts/run_sv2v_probe.sh
```

Quartus analysis/elaboration:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl6_snitch_checked_rom_mmio_led
./scripts/quartus_preflight.sh
```

Full Quartus compile:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl6_snitch_checked_rom_mmio_led
./scripts/build.sh
```

Program the board:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl6_snitch_checked_rom_mmio_led
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
```

Quartus full compile summary:

```text
device:              5CSEMA5F31C6
ALMs:                102 / 32,070 (<1%)
registers:           97
pins:                15 / 457 (3%)
block memory bits:   0 / 4,065,280 (0%)
DSP blocks:          0 / 87 (0%)
worst setup slack:   9.572 ns
worst hold slack:    0.175 ns
```

The generated ROM manifest for the default payload reports:

```text
ROM words: 4 / 64
ROM bytes: 16
SHA-256:   1997702bbdfc9528d39b5fd3ff16e8f121cbf5b3089afb62b11c2c26dcba401e
```

The programmed bitstream targets device index 2 in the DE1-SoC JTAG chain:

```text
5CSEMA5F31@2
```

## What This Proves

If the build and board test pass, SL6 proves:

```text
The generated ROM flow is safer than SL5.
The payload can be changed without editing RTL.
Oversized or malformed ROM binaries fail early.
Snitch still fetches generated ROM instructions and writes MMIO LED state.
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

After SL6, the next hardware step is SL7: add a tiny data RAM so Snitch can
perform a store/load/check sequence instead of only writing MMIO.
