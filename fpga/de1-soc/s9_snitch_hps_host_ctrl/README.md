# Snitch-Lite S9: HPS Host Control

S9 is the direct continuation after D3.

It keeps the working D3 host path:

```text
ARM Linux
  -> /dev/mem
  -> lightweight HPS-to-FPGA bridge at 0xff200000
  -> Avalon-MM slave registers
```

and replaces the D3 toy register accelerator with the S8 Snitch-Lite
control/status block:

```text
ARM Linux
  -> HPS lightweight bridge
  -> Snitch-Lite control/status registers
  -> real Snitch core running the RAM-check ROM payload
```

This is not full Occamy. It is the first DE1-SoC proof that the board's ARM
Linux host can control the Snitch-Lite accelerator path.

## Register Map

Offsets are byte offsets from the lightweight bridge base, `0xff200000`.

```text
┌────────┬─────────────┬────────┬──────────────────────────────────────┐
│ Offset │ Name        │ Access │ Meaning                              │
├────────┼─────────────┼────────┼──────────────────────────────────────┤
│ 0x00   │ ID          │ R      │ 0x53380001, inherited S8 block ID     │
│ 0x04   │ CONTROL     │ W      │ bit0=start, bit1=clear               │
│ 0x08   │ STATUS      │ R      │ bit0=done, bit1=busy, bit2=pass      │
│        │             │        │ bit3=fail, bit4=started-or-done      │
│ 0x0c   │ RESULT      │ R      │ Snitch result pattern                │
│ 0x10   │ START_COUNT │ R      │ Number of accepted start commands    │
│ 0x14   │ RUN_CYCLES  │ R      │ Cycles spent in the current/last run  │
│ 0x18   │ ROM_WORDS   │ R      │ Generated ROM word count             │
│ 0x1c   │ RAM0        │ R      │ First local RAM word after Snitch run │
└────────┴─────────────┴────────┴──────────────────────────────────────┘
```

Expected successful result:

```text
STATUS      = 0x00000015
RESULT      = 0x000001a5
RAM0        = 0x000000a5
```

`STATUS=0x15` means:

```text
done = 1
pass = 1
started-or-done = 1
```

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s9_snitch_hps_host_ctrl
./scripts/build.sh
./scripts/build_arm_tester.sh
```

The build script reuses the S8 Snitch-Lite RTL generation flow, copies the
generated Snitch-Lite Verilog into this project, creates the HPS Platform
Designer system, runs Quartus map/fit/assembler/timing, and writes both `.sof`
and `.rbf`.

Like D3, this project neutralizes the generated HPS SDRAM SDC file because the
educational bridge-only design does not export the HPS DDR pins.

## Program And Run

Program the FPGA through USB-Blaster/JTAG:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s9_snitch_hps_host_ctrl
./scripts/program.sh
```

Transfer the ARM tester over the UART console using the D3 serial helper:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/serial_transfer.py bootstrap
./scripts/serial_transfer.py send \
  ../s9_snitch_hps_host_ctrl/build/s9_mmio_nolibc \
  /tmp/s9_mmio_nolibc
```

Run from the DE1-SoC ARM Linux shell:

```bash
for b in lwhps2fpga hps2fpga fpga2hps; do
  echo 1 > /sys/class/fpga-bridge/$b/enable
done

chmod +x /tmp/s9_mmio_nolibc
/tmp/s9_mmio_nolibc
```

Expected output:

```text
ID          = 0x53380001
STATUS_CLR  = 0x00000000
STATUS      = 0x00000015
RESULT      = 0x000001a5
START_COUNT = 0x00000001
RUN_CYCLES  = 0x0000000b
ROM_WORDS   = 0x0000000e
RAM0        = 0x000000a5
PASS
```

`RUN_CYCLES` can vary slightly if the Snitch payload or shell changes.

## Verified Result

Verified on the local DE1-SoC on 2026-07-03:

```text
Snitch-Lite software ROM build: PASS
sv2v translation:              PASS
Yosys structural probe:        PASS
Qsys generation:               PASS
Quartus map:                   PASS
Quartus fit:                   PASS
Quartus assembler:             PASS
Quartus timing analysis:       PASS, positive slack
RBF conversion:                PASS
JTAG .sof programming:         PASS
ARM tester build:              PASS
UART tester transfer:          PASS
ARM Linux MMIO runtime test:   PASS
```

Board runtime transcript:

```text
bridges: lwhps2fpga=1 hps2fpga=1 fpga2hps=1
ID          = 0x53380001
STATUS_CLR  = 0x00000000
STATUS      = 0x00000015
RESULT      = 0x000001a5
START_COUNT = 0x00000001
RUN_CYCLES  = 0x0000000b
ROM_WORDS   = 0x0000000e
RAM0        = 0x000000a5
PASS
TEST_RC=0
```

## What This Proves

```text
ARM Linux can control the Snitch-Lite register block through the HPS bridge.
ARM Linux can clear/start Snitch-Lite.
ARM Linux can poll done/pass/fail.
ARM Linux can read Snitch-produced result data.
The Snitch core still performs the S7/S8 store/load/compare payload internally.
```

## What This Still Does Not Prove

```text
No runtime payload loading yet.
No interrupts.
No DMA.
No full Snitch cluster.
No full Occamy.
```
