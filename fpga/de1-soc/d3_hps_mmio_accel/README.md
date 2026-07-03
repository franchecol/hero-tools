# DE1-SoC D3 HPS MMIO Accelerator

D3 is the first ARM/Linux-controlled FPGA milestone.

It takes the D2 register accelerator and changes only the host path:

```text
D2:
  PC
    -> USB-Blaster/JTAG
    -> JTAG-to-Avalon master
    -> FPGA MMIO registers

D3:
  ARM Linux on the DE1-SoC HPS
    -> /dev/mem
    -> lightweight HPS-to-FPGA bridge at 0xff200000
    -> FPGA MMIO registers
```

This is still not Snitch-Lite. It is the smallest bridge proof before putting
the S8-style Snitch-Lite control block behind the ARM/HPS host.

## Register Map

Offsets are byte offsets from the lightweight bridge base, `0xff200000`.

```text
┌────────┬─────────────┬────────┬──────────────────────────────────────┐
│ Offset │ Name        │ Access │ Meaning                              │
├────────┼─────────────┼────────┼──────────────────────────────────────┤
│ 0x00   │ ID          │ R      │ Always 0x44330001                    │
│ 0x04   │ CONTROL     │ W      │ bit0=start, bit1=clear               │
│ 0x08   │ STATUS      │ R      │ bit0=done, bit1=busy                 │
│ 0x0c   │ A           │ R/W    │ operand A, low 8 bits                │
│ 0x10   │ B           │ R/W    │ operand B, low 8 bits                │
│ 0x14   │ OPCODE      │ R/W    │ 0=ADD, 1=XOR, 2=AND, 3=OR            │
│ 0x18   │ RESULT      │ R      │ result, low 8 bits                   │
│ 0x1c   │ CYCLES      │ R      │ number of started operations         │
└────────┴─────────────┴────────┴──────────────────────────────────────┘
```

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/build.sh
```

The build script:

```text
regenerates d3_hps_mmio_system.qsys
generates the Platform Designer HDL/QIP
patches the bridge-only HPS setting if Quartus saves it incorrectly
runs Quartus map, fit, assembler, and timing analysis
converts the .sof to .rbf for optional Linux-side FPGA Manager loading
```

Verified host build status:

```text
Qsys generation:          PASS
Quartus map:              PASS
Quartus fit:              PASS
Quartus assembler:        PASS
Quartus timing analysis:  PASS, positive slack
RBF conversion:           PASS
ARM tester build:         PASS, static ARM EABI executable
UART file transfer:       PASS
JTAG .sof programming:    PASS
Board MMIO runtime test:  PASS
Linux FPGA Manager load:  BLOCKED by MSEL setting, optional path only
```

### Quartus HPS SDRAM Workaround

D3 only uses the lightweight HPS-to-FPGA bridge. It does not export the HPS DDR
memory pins from Platform Designer.

Quartus 25.1 Lite can still generate an HPS SDRAM timing script,
`hps_sdram_p0.sdc`, and that script aborts fitting because it cannot find the
unexported DDR pins. `scripts/build.sh` intentionally empties that generated
SDC file after generation/map.

For this D3 bridge-only experiment, that is acceptable because the FPGA design
is not implementing or timing an FPGA-side DDR memory interface. For a real
HPS-heavy design, the cleaner path is to start from the official DE1-SoC HPS
Platform Designer reference/preset and keep the proper HPS pin exports,
handoff, and timing constraints.

## Program Options

Fast path while USB-Blaster is connected:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/program.sh
```

## Manual Replay Steps

These are the exact high-level steps that reproduced D3 on the local board:

```text
1. Boot the DE1-SoC ARM Linux image from microSD.
2. Confirm UART shell access as root on /dev/ttyUSB0.
3. Connect USB-Blaster and confirm `quartus_pgm --list` sees `DE-SoC [1-1]`.
4. Build the D3 FPGA project with `./scripts/build.sh`.
5. Build the ARM tester with `./scripts/build_arm_tester.sh`.
6. Program the FPGA with `./scripts/program.sh`.
7. Bootstrap the UART receiver with `./scripts/serial_transfer.py bootstrap`.
8. Transfer `build/d3_mmio_nolibc` to `/tmp/d3_mmio_nolibc`.
9. Enable `lwhps2fpga`, `hps2fpga`, and `fpga2hps` bridge nodes from Linux.
10. Run `/tmp/d3_mmio_nolibc`.
11. Confirm ID `0x44330001`, RESULT `0x00000008`, and `PASS`.
```

Linux-side path after copying the `.rbf` to the ARM board:

```bash
cat output_files/de1_d3_hps_mmio_accel.rbf > /dev/fpga0
echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable
```

If the old Terasic image requires bridge disable before programming:

```bash
echo 0 > /sys/class/fpga-bridge/lwhps2fpga/enable
cat output_files/de1_d3_hps_mmio_accel.rbf > /dev/fpga0
echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable
```

## Build The ARM Tester

The Terasic console image has no target compiler, so the included target tools
are tiny no-libc ARM Linux binaries built on the host with `clang`:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/build_arm_tester.sh
```

Expected output:

```text
build/d3_mmio_nolibc: ELF 32-bit LSB executable, ARM, EABI5
build/d3_serial_recv: ELF 32-bit LSB executable, ARM, EABI5
```

`d3_mmio_nolibc` is the MMIO test program.

`d3_serial_recv` is a tiny raw UART receiver used because this old Yocto image
has no `base64` command. It receives an exact byte count from stdin and writes
it to a target file.

## UART Transfer Helper

When Ethernet is unavailable and only the UART console works, build the ARM
tools and bootstrap the receiver:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/build_arm_tester.sh
./scripts/serial_transfer.py bootstrap
```

Then send the tester:

```bash
./scripts/serial_transfer.py send \
  build/d3_mmio_nolibc \
  /tmp/d3_mmio_nolibc
```

Then send the RBF. This is slow over 115200 baud UART:

```bash
./scripts/serial_transfer.py send --progress \
  output_files/de1_d3_hps_mmio_accel.rbf \
  /tmp/de1_d3_hps_mmio_accel.rbf
```

Verified local board transfer on 2026-07-03:

```text
/tmp/d3_serial_recv MD5:          f015cb8514756a4923d05eb31d580073
/tmp/d3_mmio_nolibc MD5:          3994d602a75e99cddd786dd4257c913e
/tmp/de1_d3_hps_mmio_accel.rbf MD5: 50435cf8216fdbf83fbc5a1c1c4bf84c
```

After the FPGA is programmed, run:

```bash
chmod +x d3_mmio_nolibc
./d3_mmio_nolibc
```

Expected successful readback:

```text
ID      = 0x44330001
STATUS  = 0x00000001
RESULT  = 0x00000008
CYCLES  = 0x00000001
PASS
```

## Verified Board Runtime

Verified on 2026-07-03 with USB-Blaster/JTAG programming:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/program.sh
```

Quartus programmed the FPGA device at JTAG index `@2`:

```text
Info (209007): Configuration succeeded -- 1 device(s) configured
Info (209011): Successfully performed operation(s)
```

Then the ARM Linux shell enabled the bridges and ran the tester:

```text
bridges: lwhps2fpga=1 hps2fpga=1 fpga2hps=1
ID      = 0x44330001
STATUS  = 0x00000001
RESULT  = 0x00000008
CYCLES  = 0x00000001
PASS
TEST_RC=0
```

So D3 is now board-MMIO-proven through the JTAG `.sof` programming path.

## Linux FPGA Manager Note

The RBF was successfully transferred to the board over UART, but Linux-side FPGA
programming failed on this board state:

```text
cat /tmp/de1_d3_hps_mmio_accel.rbf > /dev/fpga0
altera_fpga_manager ff706000.fpgamgr: Invalid MSEL setting
```

The bridge nodes were present and re-enabled:

```text
/sys/class/fpga-bridge/lwhps2fpga/enable = 1
/sys/class/fpga-bridge/hps2fpga/enable   = 1
/sys/class/fpga-bridge/fpga2hps/enable   = 1
```

The DE1-SoC user manual documents that Linux/application-side FPGA
reconfiguration needs the HPS software configuration MSEL setting, commonly
listed as `MSEL[4:0] = 01010`; some DE1-SoC demo instructions also mention
`01010` or `01110`.

This does not block D3, because the JTAG `.sof` programming path passed. It only
means Linux-side `.rbf` loading needs the board MSEL/boot-switch path fixed
before relying on FPGA Manager.

## What This Proves

```text
ARM Linux can map the FPGA lightweight bridge.
ARM Linux can write FPGA accelerator registers.
ARM Linux can poll FPGA status.
ARM Linux can read a computed FPGA result.
```

## What This Still Does Not Prove

```text
No Snitch-Lite behind the HPS bridge yet.
No runtime payload loader.
No interrupts.
No DMA.
No full Occamy.
```

The next step after D3 passes is S9/HPS-Snitch-Lite: replace the D2 register
accelerator with the S8 Snitch-Lite control/status block and keep the same
ARM/Linux host path.
