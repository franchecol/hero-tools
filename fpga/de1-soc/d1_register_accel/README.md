# DE1-SoC D1 Register Accelerator Smoke Test

This is the next FPGA-only step after D0.

D0 proved that Quartus can program the FPGA and that switches/LEDs work.
D1 adds a tiny stateful "accelerator-like" datapath:

```text
switches/buttons -> internal registers -> tiny operation -> result/status
```

It still does not use:

```text
ARM Linux
microSD
HPS-to-FPGA bridge
Snitch
Occamy
```

## Behavior

The design has two 8-bit operand registers, one opcode register, a result
register, and simple busy/done status bits.

```text
SW[7:0]   = data input
SW[9:8]   = opcode selected when KEY3 is pressed

KEY0      = clear registers/status
KEY1      = load operand A from SW[7:0]
KEY2      = load operand B from SW[7:0]
KEY3      = start operation

LEDR[7:0] = result
LEDR[8]   = done
LEDR[9]   = busy

HEX5:HEX4 = operand A
HEX3:HEX2 = operand B
HEX1:HEX0 = result
```

Opcodes:

```text
SW[9:8] = 00 -> A + B
SW[9:8] = 01 -> A XOR B
SW[9:8] = 10 -> A AND B
SW[9:8] = 11 -> A OR B
```

## Manual Test

1. Press `KEY0` to clear.
2. Set `SW[7:0]` to an operand A value.
3. Press `KEY1`.
4. Set `SW[7:0]` to an operand B value.
5. Press `KEY2`.
6. Set `SW[9:8]` to the operation.
7. Press `KEY3`.
8. `LEDR[9]` turns on briefly as `busy`.
9. `LEDR[8]` turns on when `done`.
10. `LEDR[7:0]` and `HEX1:HEX0` show the result.

Example:

```text
A = 0x03
B = 0x05
opcode = 00
result = 0x08
```

## Build

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d1_register_accel
./scripts/build.sh
```

The output bitstream is:

```text
output_files/de1_d1_register_accel.sof
```

## Program

Connect the DE1-SoC USB-Blaster cable and run:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/d1_register_accel
./scripts/program.sh
```

This programs the FPGA SRAM only. The design disappears after board reset or
power cycle.

