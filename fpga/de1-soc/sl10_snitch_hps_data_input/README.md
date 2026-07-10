# Snitch-Lite SL10: HPS Host Data Input

SL10 continues after SL9.

SL9 proved that ARM Linux can clear/start Snitch-Lite and read its fixed result.
SL10 adds the first real host-to-Snitch data path:

```text
ARM Linux
  -> /dev/mem
  -> lightweight HPS-to-FPGA bridge at 0xff200000
  -> Avalon-MM input registers
  -> Snitch-Lite local RAM
  -> real Snitch core computes result
  -> ARM Linux reads result/status/RAM back
```

This is still not full Occamy. It is an educational accelerator contract:
the host provides input data, starts the accelerator, and reads the computed
result.

## Register Map

Offsets are byte offsets from the lightweight bridge base, `0xff200000`.

```text
┌────────┬─────────────┬────────┬──────────────────────────────────────┐
│ Offset │ Name        │ Access │ Meaning                              │
├────────┼─────────────┼────────┼──────────────────────────────────────┤
│ 0x00   │ ID          │ R      │ 0x53100001                           │
│ 0x04   │ CONTROL     │ W      │ bit0=start, bit1=clear               │
│ 0x08   │ STATUS      │ R      │ bit0=done, bit1=busy, bit2=pass      │
│        │             │        │ bit3=fail, bit4=started-or-done      │
│ 0x0c   │ RESULT      │ R      │ Snitch-computed ARG0 + ARG1          │
│ 0x10   │ START_COUNT │ R      │ Number of accepted start commands    │
│ 0x14   │ RUN_CYCLES  │ R      │ Cycles spent in the current/last run  │
│ 0x18   │ ROM_WORDS   │ R      │ Generated ROM word count             │
│ 0x1c   │ RAM0        │ R      │ Snitch local RAM word 0              │
│ 0x20   │ ARG0        │ R/W    │ Host input copied to RAM0 on start    │
│ 0x24   │ ARG1        │ R/W    │ Host input copied to RAM1 on start    │
│ 0x28   │ EXPECTED    │ R/W    │ Expected result used for pass/fail    │
│ 0x2c   │ RAM1        │ R      │ Snitch local RAM word 1              │
│ 0x30   │ RAM2        │ R      │ Snitch result store location          │
└────────┴─────────────┴────────┴──────────────────────────────────────┘
```

## Expected Operation

The ARM host does this:

```text
write CONTROL.clear
write ARG0
write ARG1
write EXPECTED = ARG0 + ARG1
write CONTROL.start
poll STATUS.done
check STATUS.pass
check RESULT == EXPECTED
check RAM0/RAM1/RAM2
```

The Snitch payload does this:

```text
load RAM0
load RAM1
add them
store result to RAM2
write result to internal done/result MMIO
park forever
```

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl10_snitch_hps_data_input
./scripts/build.sh
./scripts/build_arm_tester.sh
```

The build script compiles the RV32E Snitch payload, converts it to generated
ROM contents, translates the Snitch-Lite SystemVerilog through `sv2v`, checks
it with Yosys, creates the HPS Platform Designer system, runs Quartus
map/fit/assembler/timing, and writes `.sof`/`.rbf`.

Like D3/SL9, this project neutralizes the generated HPS SDRAM SDC file because
the educational bridge-only design does not export the HPS DDR pins.

## Program And Run

Program the FPGA through USB-Blaster/JTAG:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl10_snitch_hps_data_input
./scripts/program.sh
```

Transfer the ARM tester over the UART console using the D3 serial helper:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/serial_transfer.py bootstrap
./scripts/serial_transfer.py send \
  ../sl10_snitch_hps_data_input/build/s10_mmio_nolibc \
  /tmp/s10_mmio_nolibc
```

Run from the DE1-SoC ARM Linux shell:

```bash
for b in lwhps2fpga hps2fpga fpga2hps; do
  echo 1 > /sys/class/fpga-bridge/$b/enable
done

chmod +x /tmp/s10_mmio_nolibc
/tmp/s10_mmio_nolibc
```

Expected output includes two passing runs without reprogramming:

```text
ID          = 0x53100001
ROM_WORDS   = 0x00000009
RUN0_STATUS = 0x00000015
RUN0_RESULT = 0x000001a5
RUN0_RAM0 = 0x00000100
RUN0_RAM1 = 0x000000a5
RUN0_RAM2   = 0x000001a5
START_COUNT = 0x00000001
RUN1_STATUS = 0x00000015
RUN1_RESULT = 0x00000255
RUN1_RAM0 = 0x00000200
RUN1_RAM1 = 0x00000055
RUN1_RAM2   = 0x00000255
START_COUNT = 0x00000002
PASS
```

`STATUS=0x15` means:

```text
done = 1
pass = 1
started-or-done = 1
```

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
bridge lwhps2fpga=1
bridge hps2fpga=1
bridge fpga2hps=1
ID          = 0x53100001
ROM_WORDS   = 0x00000009
RUN0_STATUS = 0x00000015
RUN0_RESULT = 0x000001a5
RUN0_RAM0 = 0x00000100
RUN0_RAM1 = 0x000000a5
RUN0_RAM2 = 0x000001a5
START_COUNT = 0x00000001
RUN_CYCLES  = 0x0000000a
RUN1_STATUS = 0x00000015
RUN1_RESULT = 0x00000255
RUN1_RAM0 = 0x00000200
RUN1_RAM1 = 0x00000055
RUN1_RAM2 = 0x00000255
START_COUNT = 0x00000002
RUN_CYCLES  = 0x0000000a
PASS
TEST_RC=0
```

Quartus full compile summary:

```text
device:              5CSEMA5F31C6
logic cells:         2,286 after synthesis
map result:          0 errors, 111 warnings
fit result:          0 errors, 4 warnings
assembler result:    0 errors, 1 warning
timing result:       0 errors, 0 warnings
worst setup slack:   6.556 ns
worst hold slack:    0.164 ns
```

## What This Proves

```text
ARM Linux can pass input data to the Snitch-Lite block before start.
Snitch can consume that data through its local memory interface.
Snitch can produce a result based on host-provided data.
The host can run the accelerator more than once without reprogramming FPGA.
```

## What This Still Does Not Prove

```text
No runtime instruction/payload loading yet.
No interrupts.
No DMA.
No full Snitch cluster.
No full Occamy.
```
