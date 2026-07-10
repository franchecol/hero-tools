# U1: Genus Snitch Core Executes ROM Software

U1 moves the U0 Genus-to-Quartus path from structural activity to
deterministic software execution.

```text
RV32E assembly
  -> RISC-V ELF and binary
  -> generated instruction ROM
  -> Genus-generic upstream Snitch core
  -> MMIO store monitor
  -> DE1-SoC LEDs
```

## Question

```text
Does the real Snitch integer core still execute a known program correctly after
original SystemVerilog -> Genus generic synthesis -> identifier sanitation ->
Quartus Cyclone V implementation?
```

## Program

The program performs four instructions:

```asm
lui  t0, 0x40000
addi t1, zero, 0x155
sw   t1, 0(t0)
j    .
```

The store targets MMIO address `0x40000000`.  The FPGA wrapper captures the
write data and exposes it on the LEDs.

## Expected Board Result

```text
LEDR[7:0] = 0x55   low software-written bits
LEDR[8]   = 1      matching MMIO write observed
LEDR[9]   = 1      reset released
```

Therefore the visible LED vector after execution should be:

```text
LEDR[9:0] = 10'b11_0101_0101 = 0x355
```

Pressing `KEY[0]` resets the core and clears the captured write.  Releasing it
should cause the program to execute again and restore `0x355`.

## Why This Is Not A Repeat Of SL5

SL5 proved the same basic ROM/MMIO software behavior through the local reduced
`sv2v` Snitch path.  U1 keeps the software action intentionally familiar but
changes the core implementation boundary:

```text
SL5:  upstream Snitch -> sv2v -> Quartus
U1: upstream Snitch -> Genus syn_generic -> sanitized names -> Quartus
```

Passing U1 therefore validates software-visible behavior across the new
external-synthesis handoff proposed after X0.

## Build And Program

The U0 generic netlist must already be present and checksum-verified under
`../u0_genus_snitch_core/build/`.  If necessary, retrieve it with:

```bash
../u0_genus_snitch_core/scripts/fetch_generic_netlist.sh
```

Then run:

```bash
./scripts/run_sim.sh
./scripts/build.sh
./scripts/program.sh
```

Generated software, ROM, sanitized netlist, Quartus databases, and `.sof` files
are ignored.  Source, scripts, constraints, and compact evidence are tracked.

## Current Status

```text
Software build:             PASS
Verilator structural sim:   PASS, LEDR=0x355
Quartus compile:            PASS
Quartus resources:          82 ALMs / 91 registers
50 MHz timing:              PASS, 13.108 ns setup slack
JTAG programming:           PASS
Physical software result:   PASS, LEDR=0x355
```

The fixed ROM lets Quartus specialize away instruction paths that this program
cannot reach, explaining the small 82-ALM result.  U0's dynamic-instruction
build remains the representative reduced-core resource measurement at 1216
ALMs and 988 registers.  U1 answers a different question: whether deterministic
software-visible behavior survives the Genus-to-Quartus handoff.

See `captures/s18_rom_mmio_2026-07-10.txt` for the compact evidence.

The user physically confirmed `LEDR[9:0] = 0x355`, completing U1.  A later
accidental board reset does not invalidate that result.  If the reset was a
power cycle or FPGA configuration reset rather than `KEY[0]`, the JTAG-loaded
image was volatile and can be restored with:

```bash
./scripts/program.sh
```
