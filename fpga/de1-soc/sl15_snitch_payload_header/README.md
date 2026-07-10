# Snitch-Lite SL15: Payload Metadata/Header

SL15 continues from SL13/SL14.

SL13 already proves:

```text
ARM Linux file
  -> raw RISC-V instruction words
  -> SL13 FPGA instruction-memory registers
  -> Snitch-Lite runs
  -> done IRQ latch asserts and clears
```

SL15 keeps the same SL13 FPGA bitstream and improves the software contract. The
payload file is no longer anonymous raw instruction words. It is now:

```text
SL15 image file
  10-word header
  RISC-V/Snitch instruction words
```

## Why This Exists

Raw instruction files work for a smoke test, but they do not say what they are:

```text
no magic
no version
no entry point
no payload word count inside the file
no declared input arguments
no declared expected result
no checksum
```

Real host/accelerator flows need a contract. SL15 is the first small contract.

## Header Format

All fields are little-endian 32-bit words:

```text
word  field
0     magic:          0x50353153  ASCII "S15P"
1     version:        1
2     header_words:   10
3     flags:          0
4     entry_word:     0
5     payload_words:  number of instruction words after the header
6     arg0:           host input copied to Snitch RAM0
7     arg1:           host input copied to Snitch RAM1
8     expected:       arg0 + arg1
9     checksum:       32-bit wrapping sum of payload instruction words
```

Then the image contains `payload_words` RV32 instruction words.

## What Runs

The default SL15 payload is still intentionally tiny:

```text
load RAM0
load RAM1
add them
store result to RAM2
write result to done MMIO
loop forever
```

The difference is that the ARM host now reads `ARG0`, `ARG1`, `EXPECTED`, and
the payload length from the SL15 image header instead of hardcoding the run data.

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl15_snitch_payload_header
./scripts/build.sh
```

Outputs:

```text
generated/sw/s15_payload.raw.bin        raw RV32 instruction bytes
generated/sw/s15_payload.img            SL15 header + raw payload
generated/sw/s15_payload_manifest.json  readable summary of the image
build/s15_header_loader_nolibc          ARM Linux loader/tester
```

Optional inputs:

```bash
S15_ARG0=0x123 S15_ARG1=0x456 ./scripts/build.sh
```

## Run On The Board

Program the SL13 bitstream first:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl13_snitch_hps_irq_done
./scripts/program.sh
```

Then transfer and run SL15:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl15_snitch_payload_header
./scripts/send_and_run.sh
```

Expected result:

```text
MAGIC = 0x50353153
VERSION = 0x00000001
HEADER_WORDS = 0x0000000a
PAYLOAD_WORDS = 0x00000009
ARG0 = 0x00000300
ARG1 = 0x00000077
EXPECTED = 0x00000377
CHECKSUM_READ = PAYLOAD_CHECKSUM
ID = 0x53130001
RUN_RESULT = 0x00000377
RUN_IRQ_PENDING = 0x00000007
RUN_IRQ_AFTER_CLEAR = 0x00000002
PASS
TEST_RC=0
```

LXDE serial-only verification:

```text
Prerequisite:
  SL13 bitstream programmed with PREPARE_LXDE_HEADLESS=1.

Command:
  BOARD_USER=ubuntu BOARD_PASSWORD=temppwd BOARD_SUDO_PASSWORD=temppwd \
    ./scripts/send_and_run.sh

Result:
  PASS
  TEST_RC=0
```

## Relation To Upstream Snitch/Occamy

This is not yet an upstream-style runtime ABI.

Upstream Snitch/Occamy uses generated memory maps, boot data, runtime support,
shared memory, and richer offload contracts. SL15 is a small educational step in
that direction: the payload file carries enough metadata for the host to reject
the wrong image before touching FPGA registers.

## What SL15 Proves

```text
The host can parse a structured accelerator payload file.
The file declares the instruction count and run arguments.
The host validates magic/version/entry/size/checksum.
The same SL13 Snitch-Lite hardware still runs and asserts done IRQ.
```

## What SL15 Does Not Prove

```text
No relocation.
No dynamic memory layout.
No multi-section ELF loading.
No reuse of the SL14 blocking IRQ consumer yet; SL15 still checks the SL13 IRQ
pending/clear register contract directly.
No upstream Snitch runtime ABI.
```
