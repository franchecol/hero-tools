# Snitch-Lite S12: HPS File Payload Loader

S12 continues after S11.

S11 proved that ARM Linux can write a tiny RISC-V instruction payload into FPGA
instruction memory. S12 keeps the same S11 FPGA bitstream and moves the payload
image out of the ARM tester binary:

```text
ARM Linux filesystem
  -> /tmp/s12_payload.bin
  -> S12 ARM loader reads the file
  -> /dev/mem
  -> lightweight HPS-to-FPGA bridge at 0xff200000
  -> S11 payload instruction-memory window
  -> CONTROL.start
  -> real Snitch core fetches the file-loaded instructions
```

This is still not full Occamy. It is a cleaner educational host/offload shape:
the host executable and the Snitch payload image are separate files.

## Hardware Requirement

S12 does not add new RTL. Program the S11 bitstream first:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s11_snitch_hps_payload_loader
./scripts/program.sh
```

This is normal after power-cycle or USB reconnect: the DE1-SoC FPGA `.sof`
configuration is volatile and must be reprogrammed unless a persistent FPGA
configuration flow is set up.

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s12_snitch_hps_file_loader
./scripts/build.sh
```

Build outputs:

```text
generated/sw/s12_payload.bin       RISC-V/Snitch payload file for ARM Linux
build/s12_file_loader_nolibc       ARM Linux loader/tester executable
generated/sw/s12_payload.dump      RISC-V disassembly for inspection
generated/sw/payload_manifest.txt  payload size and source summary
```

The payload is built from:

```text
sw/payload_sum.S
```

It is the same tiny RV32E-style payload shape as S11: load RAM0/RAM1, add them,
store to RAM2, write done/result MMIO, then park.

## Program And Run

With the S11 bitstream already programmed, transfer and run S12:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s12_snitch_hps_file_loader
./scripts/send_and_run.sh
```

Manual equivalent:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/serial_transfer.py bootstrap
./scripts/serial_transfer.py send \
  ../s12_snitch_hps_file_loader/build/s12_file_loader_nolibc \
  /tmp/s12_file_loader_nolibc
./scripts/serial_transfer.py send \
  ../s12_snitch_hps_file_loader/generated/sw/s12_payload.bin \
  /tmp/s12_payload.bin
```

Then run from the ARM Linux shell:

```bash
for b in lwhps2fpga hps2fpga fpga2hps; do
  echo 1 > /sys/class/fpga-bridge/$b/enable
done

chmod +x /tmp/s12_file_loader_nolibc
/tmp/s12_file_loader_nolibc
```

Expected output includes:

```text
PAYLOAD_FILE_BYTES = 0x00000024
PAYLOAD_FILE_WORDS = 0x00000009
ID           = 0x53110001
IMEM_CAPACITY = 0x00000010
PAYLOAD_WORDS = 0x00000009
RUN0_RESULT = 0x000001a5
RUN1_RESULT = 0x00000255
PASS
TEST_RC=0
```

## Verified Result

Verified on the local DE1-SoC board using the S11 bitstream already loaded by
USB-Blaster/JTAG.

```text
Local payload build:      pass
Local ARM loader build:   pass
UART receiver bootstrap:  pass
ARM loader transfer:      pass
Payload file transfer:    pass
FPGA bridge enable:       pass
ARM Linux runtime test:   pass
```

Runtime transcript:

```text
PAYLOAD_FILE_BYTES = 0x00000024
PAYLOAD_FILE_WORDS = 0x00000009
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
ARM Linux can keep the host loader and Snitch payload as separate files.
The host can read a payload file from Linux storage.
The host can load that file into FPGA instruction memory at runtime.
The same S11 bitstream can run file-loaded Snitch code with different inputs.
```

## What This Still Does Not Prove

```text
No persistent FPGA boot configuration yet.
No payload format with metadata or relocation.
No interrupts.
No DMA.
No full Snitch cluster.
No full Occamy.
```
