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
Board runtime test:       TODO
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

The Terasic console image has no target compiler, so the included tester is a
tiny no-libc ARM Linux binary built on the host with `clang`:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d3_hps_mmio_accel
./scripts/build_arm_tester.sh
```

Expected output:

```text
build/d3_mmio_nolibc: ELF 32-bit LSB executable, ARM, EABI5
```

Copy `build/d3_mmio_nolibc` to the DE1-SoC Linux shell, then run:

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
