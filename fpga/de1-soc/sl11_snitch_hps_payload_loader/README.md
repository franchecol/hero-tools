# Snitch-Lite SL11: HPS Payload Loader

SL11 continues after SL10.

SL10 proved that ARM Linux can pass input data to Snitch-Lite. SL11 adds the
next important piece: ARM Linux loads the Snitch instruction payload into FPGA
instruction memory at runtime.

```text
ARM Linux
  -> /dev/mem
  -> lightweight HPS-to-FPGA bridge at 0xff200000
  -> payload instruction-memory window
  -> ARG0 / ARG1 / EXPECTED registers
  -> CONTROL.start
  -> real Snitch core fetches host-loaded instructions
  -> Snitch computes result and reports done
```

This is still not full Occamy. It is the first DE1-SoC proof of the stronger
offload shape: the host provides both a tiny payload image and payload data.

## Register Map

Offsets are byte offsets from the lightweight bridge base, `0xff200000`.

```text
┌────────┬───────────────┬────────┬──────────────────────────────────────┐
│ Offset │ Name          │ Access │ Meaning                              │
├────────┼───────────────┼────────┼──────────────────────────────────────┤
│ 0x00   │ ID            │ R      │ 0x53110001                           │
│ 0x04   │ CONTROL       │ W      │ bit0=start, bit1=clear               │
│ 0x08   │ STATUS        │ R      │ bit0=done, bit1=busy, bit2=pass      │
│        │               │        │ bit3=fail, bit4=started-or-done      │
│ 0x0c   │ RESULT        │ R      │ Snitch-computed result               │
│ 0x10   │ START_COUNT   │ R      │ Number of accepted start commands    │
│ 0x14   │ RUN_CYCLES    │ R      │ Cycles spent in the current/last run  │
│ 0x18   │ IMEM_CAPACITY │ R      │ Payload instruction capacity, words   │
│ 0x1c   │ PAYLOAD_WORDS │ R/W    │ Host-written valid payload word count │
│ 0x20   │ ARG0          │ R/W    │ Host input copied to RAM0 on start    │
│ 0x24   │ ARG1          │ R/W    │ Host input copied to RAM1 on start    │
│ 0x28   │ EXPECTED      │ R/W    │ Expected result used for pass/fail    │
│ 0x2c   │ RAM0          │ R      │ Snitch local RAM word 0              │
│ 0x30   │ RAM1          │ R      │ Snitch local RAM word 1              │
│ 0x34   │ RAM2          │ R      │ Snitch result store location          │
│ 0x100  │ PAYLOAD[0]    │ R/W    │ First host-loaded instruction word    │
│ ...    │ PAYLOAD[n]    │ R/W    │ Up to 16 instruction words            │
└────────┴───────────────┴────────┴──────────────────────────────────────┘
```

## Expected Operation

The ARM tester currently embeds a tiny RISC-V payload image produced from
`sw/payload_sum.S`. At runtime it writes that image into the SL11 payload window.

```text
write CONTROL.clear
write PAYLOAD[0..n-1]
write PAYLOAD_WORDS = n
write ARG0 / ARG1 / EXPECTED
write CONTROL.start
poll STATUS.done
check RESULT and RAM state
repeat with new ARG0 / ARG1 without reprogramming the FPGA
```

The host-loaded Snitch payload does this:

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
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl11_snitch_hps_payload_loader
./scripts/build.sh
./scripts/build_arm_tester.sh
```

The FPGA bitstream is independent of the specific payload image. The ARM tester
build compiles `sw/payload_sum.S` into RISC-V instruction words and includes
them in the ARM executable so the ARM side can write them into FPGA instruction
memory at runtime.

SL11 clocks the HPS bridge-facing Qsys subsystem and Snitch-Lite core at 25 MHz
using a divide-by-two clock from `CLOCK_50`. The host-loaded instruction memory
adds a real instruction-select path, and 25 MHz keeps that educational path
timing-clean on Cyclone V.

Timing note:

```text
Initial 50 MHz attempt:
  built a bitstream, but failed setup timing through the host-loaded
  instruction-select/decode path.

Final educational version:
  16-word payload instruction memory
  25 MHz SL11 Qsys/Snitch-Lite subsystem
  corrected SDC for the divide-by-two generated clock
```

## Program And Run

Program the FPGA through USB-Blaster/JTAG:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl11_snitch_hps_payload_loader
./scripts/program.sh
```

Transfer the ARM tester over the UART console using the D3 serial helper:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/serial_transfer.py bootstrap
./scripts/serial_transfer.py send \
  ../sl11_snitch_hps_payload_loader/build/s11_mmio_nolibc \
  /tmp/s11_mmio_nolibc
```

Run from the DE1-SoC ARM Linux shell:

```bash
for b in lwhps2fpga hps2fpga fpga2hps; do
  echo 1 > /sys/class/fpga-bridge/$b/enable
done

chmod +x /tmp/s11_mmio_nolibc
/tmp/s11_mmio_nolibc
```

Expected output includes:

```text
ID            = 0x53110001
IMEM_CAPACITY = 0x00000010
PAYLOAD_WORDS = 0x00000009
RUN0_STATUS   = 0x00000015
RUN0_RESULT   = 0x000001a5
RUN1_STATUS   = 0x00000015
RUN1_RESULT   = 0x00000255
START_COUNT   = 0x00000002
PASS
```

## Verified Result

Verified on the local DE1-SoC board with Quartus Prime Lite 25.1.

```text
Build checks:
  payload_sum.S -> payload ELF/bin/words: pass
  sv2v SL11 translation:                 pass
  Yosys SL11 probe:                      pass
  Qsys generation:                      pass
  Quartus map/fit/assembler:            pass
  RBF conversion:                       pass

Final timing:
  S11_QSYS_CLK period:                  40.000 ns / 25 MHz
  worst slow setup slack:               +11.122 ns
  worst fast hold slack:                +0.077 ns
  TimeQuest warnings/errors:            0 / 0

Board checks:
  JTAG programming:                     pass
  UART transfer to ARM Linux:           pass
  ARM Linux runtime test:               pass
```

Runtime transcript:

```text
ID           = 0x53110001
IMEM_CAPACITY = 0x00000010
PAYLOAD_WORDS = 0x00000009
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

## What This Proves

```text
ARM Linux can load a tiny Snitch instruction payload at runtime.
Snitch fetches instructions from host-written FPGA instruction memory.
ARM Linux can pass data to that loaded payload.
The same bitstream can run the loaded payload more than once with new data.
```

## What This Still Does Not Prove

```text
No payload loading from an external file on the ARM filesystem yet.
No interrupts.
No DMA.
No full Snitch cluster.
No full Occamy.
```
