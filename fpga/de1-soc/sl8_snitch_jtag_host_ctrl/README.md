# Snitch-Lite SL8: JTAG Host Control

SL8 adds a temporary host-control path around the SL7 Snitch-Lite RAM check.

The temporary host is the PC through USB-Blaster/JTAG:

```text
PC System Console
      │
      ▼
USB-Blaster/JTAG
      │
      ▼
JTAG-to-Avalon master
      │
      ▼
SL8 Avalon-MM control/status registers
      │
      ▼
Snitch-Lite ROM/RAM check
```

This is deliberately shaped like the later HPS/Linux path:

```text
ARM Linux
      │
      ▼
HPS-to-FPGA bridge
      │
      ▼
same kind of control/status registers
      │
      ▼
Snitch-Lite accelerator block
```

So SL8 is the last useful pre-microSD step: it proves the register contract
before ARM Linux is available.

## Register Map

Offsets are byte offsets from the register-block base.

```text
┌────────┬─────────────┬────────┬──────────────────────────────────────┐
│ Offset │ Name        │ Access │ Meaning                              │
├────────┼─────────────┼────────┼──────────────────────────────────────┤
│ 0x00   │ ID          │ R      │ Always 0x53380001                    │
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

## Internal Snitch Memory Map

```text
0x00000000  instruction ROM, generated from sw/ram_check.S
0x00001000  tiny local data RAM, 16 words
0x40000000  internal Snitch done/result MMIO register
```

## Expected Operation

The host does this:

```text
write CONTROL.clear
read STATUS == 0
write CONTROL.start
poll STATUS.done
read RESULT == 0x000001a5
read RAM0   == 0x000000a5
```

The Snitch payload does this after the host starts it:

```text
store 0x000000a5 to 0x00001000
load  from       0x00001000
if loaded value == 0x000000a5:
    write 0x000001a5 to internal done/result MMIO
else:
    write 0x0000005a to internal done/result MMIO
park forever
```

## LED Meaning

```text
LEDR[7:0] = RESULT[7:0]
LEDR[8]   = pass
LEDR[9]   = busy
```

Expected final board pattern after the smoke test:

```text
LEDR[7:0] = 0xa5
LEDR[8]   = 1
LEDR[9]   = 0
```

## Run

Build only the software ROM and generated Snitch core:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl8_snitch_jtag_host_ctrl
./scripts/run_sv2v_probe.sh
```

Quartus analysis/elaboration:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl8_snitch_jtag_host_ctrl
./scripts/quartus_preflight.sh
```

Full Quartus compile:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl8_snitch_jtag_host_ctrl
./scripts/build.sh
```

Program the board:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl8_snitch_jtag_host_ctrl
./scripts/program.sh
```

Run the JTAG/System Console smoke test:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl8_snitch_jtag_host_ctrl
./scripts/test_mmio.sh
```

After programming, press and release `KEY0` once if the board is held in reset.
`KEY0` is the active-low reset input for this design.

## Verified Result

This stage was checked on the local DE1-SoC setup:

```text
software ROM build:              PASS
oversized ROM negative test:     PASS
sv2v translation:                PASS
Yosys structural probe:          PASS
Qsys system generation:          PASS
Quartus analysis/elaboration:    PASS
Quartus full compile:            PASS
Quartus JTAG programming:        PASS
System Console MMIO smoke test:  PASS
physical LED observation:        pending user confirmation
```

System Console readback from the programmed board:

```text
ID          = 0x53380001
STATUS clr  = 0x00000000
STATUS      = 0x00000015
RESULT      = 0x000001a5
START_COUNT = 0x00000001
RUN_CYCLES  = 0x0000000b
ROM_WORDS   = 0x0000000e
RAM0        = 0x000000a5
```

`STATUS=0x15` means:

```text
bit0 done = 1
bit2 pass = 1
bit4 started-or-done = 1
```

Quartus full compile summary:

```text
device:              5CSEMA5F31C6
ALMs:                1,141 / 32,070 (4%)
registers:           1542
pins:                15 / 457 (3%)
block memory bits:   512 / 4,065,280 (<1%)
DSP blocks:          0 / 87 (0%)
worst setup slack:   5.153 ns
worst hold slack:    0.143 ns
compile result:      0 errors, 84 warnings
```

The generated ROM manifest for the default payload reports:

```text
ROM words: 14 / 64
ROM bytes: 56
SHA-256:   e851776fd1a5def8a207537de6b884e429fd13d65e4736acb127bd61fbaa3ad4
```

The programmed bitstream targets device index 2 in the DE1-SoC JTAG chain:

```text
5CSEMA5F31@2
```

## What This Proves

If the build and smoke test pass, SL8 proves:

```text
The host can see the Snitch-Lite block as MMIO registers.
The host can clear/start the Snitch-Lite block.
The host can poll done/busy/pass/fail.
The host can read back Snitch-produced result data.
The Snitch core still performs the SL7 store/load/compare sequence internally.
```

## What This Still Does Not Prove

```text
No ARM/HPS Linux yet.
No HPS-to-FPGA bridge wiring yet.
No runtime payload loader yet.
No full Snitch cluster.
No TCDM.
No DMA.
```

After SL8, the next step that truly needs the microSD card is D3/HPS-lite:
boot ARM Linux and access an equivalent FPGA register block through the
lightweight HPS-to-FPGA bridge.

## After Booting ARM Linux

If the DE1-SoC is booted from the Terasic SD-card image and the LEDs/HEX display
show a simple counter, the FPGA is not necessarily running this SL8 bitstream.
SL8 was loaded through USB-Blaster/JTAG into volatile FPGA SRAM, so it disappears
after power/reset unless reprogrammed.

That counter is useful only as a board-alive sign. The correct follow-up is not
to treat the counter design as SL8, but to build D3:

```text
ARM Linux
  -> /dev/mem
  -> lightweight HPS-to-FPGA bridge at 0xff200000
  -> FPGA MMIO registers
  -> tiny accelerator / later Snitch-Lite block
```
