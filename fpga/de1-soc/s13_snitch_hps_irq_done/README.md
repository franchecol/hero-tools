# Snitch-Lite S13: HPS Done IRQ

S13 continues after S12.

S12 proved that ARM Linux can keep the ARM host executable and RISC-V/Snitch
payload image as separate files. S13 keeps that file-loaded payload flow and
adds a hardware done interrupt path from the Snitch-Lite wrapper into the HPS
FPGA-to-HPS interrupt input.

```text
ARM Linux filesystem
  -> /tmp/s13_payload.bin
  -> S13 ARM tester reads the file
  -> /dev/mem
  -> lightweight HPS-to-FPGA bridge at 0xff200000
  -> S13 payload instruction-memory window
  -> CONTROL.start
  -> real Snitch core fetches the file-loaded instructions
  -> Snitch writes done/result MMIO
  -> S13 wrapper latches IRQ_PENDING
  -> irq = IRQ_ENABLE && IRQ_PENDING
  -> Qsys irq_mapper
  -> hps_0.f2h_irq0, irqNumber 0
```

This is still not full Occamy. It is the next educational host/offload step:
the FPGA-side accelerator can produce an interrupt-style done signal instead
of only exposing a polled `STATUS.done` bit.

Important limitation:

```text
S13 verifies IRQ production and clear at the FPGA/MMIO level.
S13 does not yet install a Linux kernel/UIO driver that blocks on the HPS IRQ.
```

## Register Map

Offsets are byte offsets from the lightweight bridge base, `0xff200000`.

```text
┌────────┬───────────────┬────────┬──────────────────────────────────────┐
│ Offset │ Name          │ Access │ Meaning                              │
├────────┼───────────────┼────────┼──────────────────────────────────────┤
│ 0x00   │ ID            │ R      │ 0x53130001                           │
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
│ 0x2c   │ RAM0          │ R      │ Snitch local RAM word 0               │
│ 0x30   │ RAM1          │ R      │ Snitch local RAM word 1               │
│ 0x34   │ RAM2          │ R      │ Snitch result store location          │
│ 0x38   │ IRQ_ENABLE    │ R/W    │ bit0 enables the done IRQ output      │
│ 0x3c   │ IRQ_PENDING   │ R/W1C  │ read bit0=pending, bit1=enable        │
│        │               │        │ read bit2=irq line; write bit0 clears │
│ 0x100  │ PAYLOAD[0]    │ R/W    │ First host-loaded instruction word    │
│ ...    │ PAYLOAD[n]    │ R/W    │ Up to 16 instruction words            │
└────────┴───────────────┴────────┴──────────────────────────────────────┘
```

## Expected Operation

```text
write CONTROL.clear
write IRQ_PENDING = 1 to clear stale pending state
write IRQ_ENABLE = 1
read payload file from /tmp/s13_payload.bin
write PAYLOAD[0..n-1]
write PAYLOAD_WORDS = n
write ARG0 / ARG1 / EXPECTED
write CONTROL.start
wait until STATUS.done is set
check RESULT and RAM state
check IRQ_PENDING reads 0x7:
  bit0 pending = 1
  bit1 enable  = 1
  bit2 irq     = 1
write IRQ_PENDING = 1
check IRQ_PENDING reads 0x2:
  bit0 pending = 0
  bit1 enable  = 1
  bit2 irq     = 0
repeat with new ARG0 / ARG1
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
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s13_snitch_hps_irq_done
./scripts/build.sh
./scripts/build_arm_tester.sh
```

Build outputs:

```text
output_files/de1_s13_snitch_hps_irq_done.sof  JTAG-programmable FPGA image
output_files/de1_s13_snitch_hps_irq_done.rbf  Raw binary FPGA image
build/s13_irq_nolibc                          ARM Linux tester executable
generated/sw/s13_payload.bin                  RISC-V/Snitch payload file
generated/sw/s13_payload.dump                 RISC-V disassembly
```

The payload is built from:

```text
sw/payload_sum.S
```

## Program And Run

Program the FPGA through USB-Blaster/JTAG:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s13_snitch_hps_irq_done
./scripts/program.sh
```

On the Terasic LXDE Ubuntu image, use the serial-only headless preparation
before programming. This stops the vendor display path before the Snitch-Lite
fabric replaces the FPGA framebuffer design:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s13_snitch_hps_irq_done

PREPARE_LXDE_HEADLESS=1 \
BOARD_USER=ubuntu \
BOARD_PASSWORD=temppwd \
BOARD_SUDO_PASSWORD=temppwd \
./scripts/program.sh
```

Transfer and run the ARM tester plus payload over the UART console:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s13_snitch_hps_irq_done

BOARD_USER=ubuntu \
BOARD_PASSWORD=temppwd \
BOARD_SUDO_PASSWORD=temppwd \
./scripts/send_and_run.sh
```

Manual equivalent:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/serial_transfer.py bootstrap
./scripts/serial_transfer.py send \
  ../s13_snitch_hps_irq_done/build/s13_irq_nolibc \
  /tmp/s13_irq_nolibc
./scripts/serial_transfer.py send \
  ../s13_snitch_hps_irq_done/generated/sw/s13_payload.bin \
  /tmp/s13_payload.bin
```

Then run from the ARM Linux shell:

```bash
for b in lwhps2fpga hps2fpga fpga2hps; do
  echo 1 > /sys/class/fpga-bridge/$b/enable
done

chmod +x /tmp/s13_irq_nolibc
/tmp/s13_irq_nolibc
```

Expected output includes:

```text
ID           = 0x53130001
IRQ_ENABLE = 0x00000001
IRQ_PENDING = 0x00000002
RUN0_IRQ_PENDING = 0x00000007
RUN0_IRQ_AFTER_CLEAR = 0x00000002
RUN1_IRQ_PENDING = 0x00000007
RUN1_IRQ_AFTER_CLEAR = 0x00000002
PASS
TEST_RC=0
```

## Verified Result

Verified on the local DE1-SoC board with Quartus Prime Lite 25.1.

```text
Build checks:
  payload_sum.S -> payload ELF/bin:      pass
  ARM Linux tester build:                pass
  sv2v S13 translation:                  pass
  Yosys S13 probe:                       pass
  Qsys generation with f2h_irq0:         pass
  Quartus map/fit/assembler:             pass
  Quartus timing analysis:               pass
  RBF conversion:                        pass

Final fit:
  Logic utilization:                     2,596 / 32,070 ALMs (8%)
  Total registers:                       2,356
  Total pins:                            15 / 457 (3%)
  Total block memory bits:               0 / 4,065,280 (0%)
  Total PLLs:                            0 / 6 (0%)

Final timing:
  S13_QSYS_CLK period:                   40.000 ns / 25 MHz
  worst reported setup slack:            +9.612 ns
  worst reported hold slack:             +0.030 ns
  TimeQuest errors/warnings:             0 / 0

Board checks:
  JTAG programming:                      pass
  UART transfer to ARM Linux:            pass
  ARM Linux runtime test:                pass
  LXDE serial-only runtime test:         pass
```

LXDE-specific verified command sequence:

```text
PREPARE_LXDE_HEADLESS=1 BOARD_USER=ubuntu BOARD_PASSWORD=temppwd \
  BOARD_SUDO_PASSWORD=temppwd ./scripts/program.sh

BOARD_USER=ubuntu BOARD_PASSWORD=temppwd BOARD_SUDO_PASSWORD=temppwd \
  ./scripts/send_and_run.sh

Result:
  PASS
  TEST_RC=0
```

Runtime transcript:

```text
PAYLOAD_FILE_BYTES = 0x00000024
PAYLOAD_FILE_WORDS = 0x00000009
ID           = 0x53130001
IRQ_ENABLE = 0x00000001
IRQ_PENDING = 0x00000002
IMEM_CAPACITY = 0x00000010
PAYLOAD_WORDS = 0x00000009
RUN0_STATUS = 0x00000015
RUN0_RESULT = 0x000001a5
RUN0_RAM0 = 0x00000100
RUN0_RAM1 = 0x000000a5
RUN0_RAM2 = 0x000001a5
RUN0_IRQ_ENABLE = 0x00000001
RUN0_IRQ_PENDING = 0x00000007
START_COUNT = 0x00000001
RUN_CYCLES  = 0x0000000a
RUN0_IRQ_AFTER_CLEAR = 0x00000002
RUN1_STATUS = 0x00000015
RUN1_RESULT = 0x00000255
RUN1_RAM0 = 0x00000200
RUN1_RAM1 = 0x00000055
RUN1_RAM2 = 0x00000255
RUN1_IRQ_ENABLE = 0x00000001
RUN1_IRQ_PENDING = 0x00000007
START_COUNT = 0x00000002
RUN_CYCLES  = 0x0000000a
RUN1_IRQ_AFTER_CLEAR = 0x00000002
PASS
TEST_RC=0
```

## What This Proves

```text
ARM Linux can load a separate Snitch payload file at runtime.
Snitch fetches instructions from host-written FPGA instruction memory.
ARM Linux can pass data to that payload.
The Snitch-Lite wrapper can latch done as IRQ_PENDING.
The done IRQ line asserts when enabled and clears when acknowledged.
Qsys connects the interrupt sender to HPS f2h_irq0, irqNumber 0.
```

## What This Still Does Not Prove

```text
No Linux kernel driver, UIO driver, or blocking userspace interrupt wait yet.
No persistent FPGA boot configuration yet.
No payload format with metadata or relocation.
No DMA.
No full Snitch cluster.
No full Occamy.
```
