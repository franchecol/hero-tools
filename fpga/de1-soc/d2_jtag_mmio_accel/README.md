# DE1-SoC D2 JTAG MMIO Accelerator

D2 replaces the D1 button-driven "register writes" with real Avalon-MM register
writes.

For now the bus master is:

```text
PC -> USB-Blaster/JTAG -> JTAG-to-Avalon master -> FPGA MMIO registers
```

Later, the same register block can be connected to the HPS lightweight bridge:

```text
ARM Linux -> lightweight HPS-to-FPGA bridge -> FPGA MMIO registers
```

This means D2 proves the important hardware/software contract before the
microSD/Linux boot flow is ready.

## Register Map

Offsets are byte offsets from the register-block base.

```text
┌────────┬─────────────┬────────┬──────────────────────────────────────┐
│ Offset │ Name        │ Access │ Meaning                              │
├────────┼─────────────┼────────┼──────────────────────────────────────┤
│ 0x00   │ ID          │ R      │ Always 0x44320001                    │
│ 0x04   │ CONTROL     │ W      │ bit0=start, bit1=clear               │
│ 0x08   │ STATUS      │ R      │ bit0=done, bit1=busy                 │
│ 0x0c   │ A           │ R/W    │ operand A, low 8 bits                │
│ 0x10   │ B           │ R/W    │ operand B, low 8 bits                │
│ 0x14   │ OPCODE      │ R/W    │ 0=ADD, 1=XOR, 2=AND, 3=OR            │
│ 0x18   │ RESULT      │ R      │ result, low 8 bits                   │
│ 0x1c   │ CYCLES      │ R      │ number of started operations         │
└────────┴─────────────┴────────┴──────────────────────────────────────┘
```

## Board Outputs

```text
LEDR[7:0] = RESULT
LEDR[8]   = done
LEDR[9]   = busy

HEX5:HEX4 = operand A
HEX3:HEX2 = operand B
HEX1:HEX0 = result
```

`KEY0` is reset. The other keys are unused in D2.

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d2_jtag_mmio_accel
./scripts/build.sh
```

The build script regenerates the Platform Designer system before running
Quartus:

```text
d2_mmio_system.qsys
d2_mmio_system/synthesis/d2_mmio_system.qip
```

Those are generated build artifacts and are ignored by git.

## Program

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d2_jtag_mmio_accel
./scripts/program.sh
```

This programs the FPGA SRAM only. It disappears after reset or power cycle.

## Test With System Console

After programming:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d2_jtag_mmio_accel
./scripts/test_mmio.sh
```

Expected operation:

```text
write A      = 0x03
write B      = 0x05
write OPCODE = 0x00
write START
read RESULT  = 0x08
```

If it passes, the FPGA is accepting real MMIO writes and returning real MMIO
reads.

## Later HPS/Linux Test

The file below is the Linux-side shape for the future HPS test:

```text
sw/d2_mmio_user.c
```

It assumes the register block is mapped at the lightweight HPS-to-FPGA bridge
base:

```text
0xff200000
```

That part is not testable until the ARM Linux image is booted and the HPS bridge
is enabled.

