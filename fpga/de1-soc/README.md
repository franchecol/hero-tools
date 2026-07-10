# DE1-SoC FPGA Bring-Up

This directory tracks the educational DE1-SoC path toward a tiny accelerator.

It is intentionally separate from the full Occamy FPGA path. The DE1-SoC board
is useful for small staged hardware experiments, not for full Occamy.

For a feature-by-feature comparison against upstream Snitch/Occamy, including
the S13 interrupt-done path and the S14 Linux IRQ consumer, see
[`SNITCH_LITE_FEATURE_COMPARISON.md`](SNITCH_LITE_FEATURE_COMPARISON.md).

## Stages

```text
D0: LED/switch smoke test
    Proves Quartus, USB-Blaster/JTAG, FPGA programming, switches, and LEDs.

D1: register accelerator smoke test
    Adds clocked state, operand registers, opcode selection, result, busy, done,
    and 7-segment output.

D2: JTAG/PC to FPGA MMIO register access
    Replace manual buttons/switches with real Avalon-MM register writes using
    System Console over USB-Blaster/JTAG. The same register block is intended
    for the later HPS lightweight bridge.

D3: HPS/ARM Linux to FPGA MMIO register access
    Connect the same D2 register block to the HPS lightweight bridge and access
    it from ARM Linux.

S9: HPS/ARM Linux to Snitch-Lite MMIO control
    Replace the D3 toy register accelerator with the S8 Snitch-Lite control
    block behind the same HPS lightweight bridge.

S10: HPS/ARM Linux passes input data to Snitch-Lite
    ARM writes input words over MMIO, starts Snitch-Lite, and reads back the
    Snitch-computed result.

S11: HPS/ARM Linux loads a Snitch-Lite payload image
    ARM writes RISC-V instruction words into FPGA instruction memory, writes
    ARG0/ARG1/EXPECTED, starts Snitch-Lite, and reads back the result.

S12: HPS/ARM Linux loads the payload from a file
    Reuse the S11 bitstream, but keep the ARM host loader and Snitch payload
    image as separate Linux files.

S13: HPS/ARM Linux observes a Snitch-Lite done IRQ
    Add an FPGA-side done interrupt latch, connect it to HPS f2h_irq0 through
    Qsys, and verify IRQ enable/pending/clear from ARM Linux.

S14: HPS/ARM Linux IRQ consumer
    Build a matching kernel module for the current Terasic Linux image,
    register f2h_irq0, expose /dev/snitch_lite_irq, and wake userspace from a
    blocking interrupt wait.

S15: HPS/ARM Linux loads a headered Snitch-Lite payload image
    Reuse the S13 bitstream, but load a structured payload image with
    magic/version/entry/word-count/arguments/checksum metadata.

S16: external gate-level netlist import probe
    Test the professor-proposed path on a toy design: synthesize RTL with
    Genus, import the generated gate-level netlist into Quartus through small
    compatibility shims, and compile it for Cyclone V.

S17: direct Genus Snitch-core synthesis
    Feed the original upstream reduced Snitch integer-core SystemVerilog to
    Genus without sv2v, map it to TSMC65 cells, and validate the mapped core in
    Questa before testing a scalable Quartus import boundary.
```

## Current Board State After microSD Boot

The Terasic SD-card Linux image can load or leave running a default FPGA demo.
If the board is counting through `0,1,2,3,...,f`, that is not evidence that the
S8 Snitch-Lite bitstream is still loaded.

```text
S8 bitstream loaded by USB-Blaster/JTAG: volatile, lost after power/reset.
Terasic demo/counter bitstream:          useful only as a board-alive sign.
D3 target:                               ARM Linux controls FPGA over HPS bridge.
```

Do not test the D2/S8 register map against the counter demo. The next useful
test is D3: program an HPS-connected register block and access it from Linux at
the lightweight bridge base, `0xff200000`.

## LXDE Image, Serial-Only Use

The Terasic LXDE Ubuntu image can be used as a serial-only Linux host. The
desktop is not required for the Snitch-Lite experiments.

Before JTAG-programming a custom Snitch-Lite `.sof` while LXDE is running, stop
the GUI/display path first:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s13_snitch_hps_irq_done

PREPARE_LXDE_HEADLESS=1 \
BOARD_USER=ubuntu \
BOARD_PASSWORD=temppwd \
BOARD_SUDO_PASSWORD=temppwd \
./scripts/program.sh
```

Why: the LXDE image boots a vendor FPGA framebuffer/display design. If Linux is
still using that display IP when JTAG replaces the fabric with Snitch-Lite, the
HPS serial console can freeze. `PREPARE_LXDE_HEADLESS=1` runs:

```text
stop lightdm / graphical target
unbind the altvipfb framebuffer driver if present
leave the FPGA bridges visible/enabled
then program the Snitch-Lite bitstream
```

Then run the host test over UART:

```bash
BOARD_USER=ubuntu \
BOARD_PASSWORD=temppwd \
BOARD_SUDO_PASSWORD=temppwd \
./scripts/send_and_run.sh
```

The no-libc ARM host programs use raw Linux syscalls. Their `/dev/mem` mapping
checks must use the Linux syscall error convention, not `mapped < 0`, because
valid 32-bit ARM user pointers can have the high bit set.

## Current Projects

```text
d0_led_switches/
  SW[9:0] -> LEDR[9:0]

d1_register_accel/
  KEY/SW-controlled mini accelerator:
  A register, B register, opcode, busy, done, result

d2_jtag_mmio_accel/
  System Console/JTAG-controlled mini accelerator:
  Avalon-MM register block, ID/status/control/data/result registers

s0_snitch_verilator/
  Real-Snitch simulation path:
  one-core Snitch config, tiny bare-metal ELF, Verilator testbench

s1_snitch_mmio_trace/
  Real-Snitch simulated MMIO path:
  one-core Snitch config, fake MMIO store, trace-checked result

s2_snitch_quartus_wrapper/
  Quartus-facing Snitch wrapper path:
  one-core Snitch config, Bender-to-QSF export, analysis/elaboration preflight.
  Current result: export works; Quartus Lite reaches Snitch RTL and then stops
  on unsupported advanced SystemVerilog syntax.

s3_snitch_core_only_probe/
  Reduced real-Snitch path:
  instantiate snitch.sv directly, add tiny local shims, and probe the smaller
  core-only subset with sv2v/yosys before trying Quartus again.
  Current result: sv2v, Yosys, Quartus analysis/elaboration, and full Quartus
  compile pass. A .sof is produced, but S3 still uses a constant NOP input and
  Quartus optimizes away most unused core behavior.

s4_snitch_rom_mmio_led/
  First board-visible real-Snitch shell:
  feed Snitch a tiny ROM program, accept its MMIO store, and expose the written
  value on LEDR.

s5_snitch_generated_rom_mmio_led/
  Software-generated ROM path:
  compile RV32E assembly into an ELF/binary, generate ROM contents, and reuse
  the Snitch MMIO LED proof with software-owned instruction words.

s6_snitch_checked_rom_mmio_led/
  Checked software-generated ROM path:
  add max-size checks, entry-address checks, generated metadata, and a
  configurable assembly source path around the S5 flow.

s7_snitch_tiny_ram_check/
  Tiny data-RAM check path:
  Snitch stores to local FPGA RAM, loads the value back, checks it, and reports
  pass/fail through LED MMIO.

s8_snitch_jtag_host_ctrl/
  Temporary host-control path:
  expose Snitch-Lite start/done/pass/fail/result registers through a
  JTAG-to-Avalon master before the ARM/HPS Linux microSD flow is available.

d3_hps_mmio_accel/
  ARM/HPS Linux-controlled mini accelerator:
  expose the D2-style register block through the HPS lightweight bridge and
  test it from the ARM Linux shell.
  Current result: Qsys generation, Quartus map/fit/assembler/timing, RBF
  conversion, ARM tester cross-build, UART file transfer, JTAG programming,
  and ARM Linux MMIO runtime test pass. Linux-side FPGA Manager `.rbf` loading
  remains blocked by the board MSEL setting, but that is optional for D3.

s9_snitch_hps_host_ctrl/
  ARM/HPS Linux-controlled Snitch-Lite accelerator:
  expose the S8 Snitch-Lite control/status block through the HPS lightweight
  bridge and test it from the ARM Linux shell.
  Current result: Snitch-Lite generation, Qsys generation, Quartus
  map/fit/assembler/timing, RBF conversion, JTAG programming, ARM tester
  cross-build, UART transfer, and ARM Linux MMIO runtime test pass.

s10_snitch_hps_data_input/
  ARM/HPS Linux-controlled Snitch-Lite data-input accelerator:
  ARM writes ARG0/ARG1/EXPECTED registers, Snitch consumes ARG0/ARG1 from
  local RAM, computes ARG0 + ARG1, stores the result to RAM2, and reports done.
  Current result: Snitch-Lite payload generation, sv2v, Yosys, Qsys, Quartus
  map/fit/assembler/timing, RBF conversion, JTAG programming, ARM tester
  cross-build, UART transfer, and two ARM Linux MMIO runtime runs pass.

s11_snitch_hps_payload_loader/
  ARM/HPS Linux-controlled Snitch-Lite payload loader:
  ARM writes a tiny RISC-V instruction payload into FPGA instruction memory,
  writes ARG0/ARG1/EXPECTED registers, starts Snitch-Lite, and reads back the
  Snitch-computed result.
  Current result: payload build, sv2v, Yosys, Qsys, Quartus
  map/fit/assembler/timing, RBF conversion, JTAG programming, ARM tester
  cross-build, UART transfer, and two ARM Linux MMIO runtime payload runs pass.

s12_snitch_hps_file_loader/
  ARM/HPS Linux file-payload loader:
  reuse the S11 FPGA bitstream, transfer an ARM loader executable plus a
  separate RISC-V payload binary to Linux, and have the ARM loader read the
  payload file before writing it into FPGA instruction memory.
  Current result: local software build, UART transfer of separate host/payload
  files, S11-bitstream reuse, and ARM Linux runtime file-payload test pass.

s13_snitch_hps_irq_done/
  ARM/HPS Linux Snitch-Lite done-IRQ path:
  add IRQ_ENABLE and IRQ_PENDING registers to the S11/S12 payload-loader
  hardware, connect the wrapper interrupt sender to HPS f2h_irq0 through Qsys,
  and verify from ARM Linux that the done IRQ line asserts and clears.
  Current result: payload build, ARM tester build, sv2v, Yosys, Qsys, Quartus
  map/fit/assembler/timing, RBF conversion, JTAG programming, UART transfer,
  and ARM Linux MMIO runtime IRQ-pending/clear test pass. The same S13 runtime
  path is verified on the LXDE Ubuntu image when `PREPARE_LXDE_HEADLESS=1` is
  used before JTAG programming.

s14_snitch_hps_irq_linux/
  ARM/HPS Linux IRQ consumer:
  build/load a matching snitch_lite_irq.ko module, register the f2h_irq0
  interrupt, expose /dev/snitch_lite_irq, block userspace in read()/poll(),
  and wake on Snitch-Lite completion.
  Current result on the older console image: S13 bitstream programming passes,
  the module vermagic matches 3.12.0-00307-g507abb4-dirty, insmod registers GIC
  IRQ 72, userspace wakes twice from real Snitch completions, /proc/interrupts
  increments by two, and TEST_RC=0. Current result on the LXDE image: the
  module vermagic matches 4.5.0-00183-g4647b69-dirty, the driver maps Qsys
  f2h_irq0/GIC SPI 40 to Linux virtual IRQ 131, userspace wakes twice from real
  Snitch completions, /proc/interrupts increments by two, and TEST_RC=0.

s15_snitch_payload_header/
  ARM/HPS Linux Snitch-Lite payload-header path:
  reuse the S13 bitstream, but transfer a structured S15 image with
  magic/version/entry/word-count/arguments/checksum metadata before the RISC-V
  instruction words.
  Current result: local payload-image build, ARM loader cross-build, UART
  transfer, S13-bitstream reuse, header validation, Snitch-Lite execution, done
  IRQ pending/clear check, and ARM Linux runtime test pass. This now also
  passes on the LXDE Ubuntu serial-only path after the S13 headless-prepared
  bitstream is programmed.

s16_gatelevel_quartus_import/
  External gate-level netlist import probe:
  use a Cadence Genus-generated TSMC65 toy counter netlist, provide tiny public
  compatibility shims for the generated cell names, wrap it for DE1-SoC
  CLOCK_50/KEY/SW/LEDR pins, and compile it in Quartus.
  Current result: Quartus Lite 25.1 analysis/synthesis, fitter, assembler, and
  timing pass for Cyclone V with 0 errors and 2 fitter warnings. JTAG
  programming of device `5CSEMA5F31@2` also passes with 0 errors; direct visual
  confirmation of the SW/KEY/LED counter behavior also passes.

s17_genus_snitch_core/
  Direct external synthesis of a meaningful upstream Snitch integer core:
  Genus reads the original package-heavy SystemVerilog without sv2v, preserves
  dynamic instruction and data-request behavior, and maps the reduced core to
  3296 TSMC65 cells with area 12413.520. Questa gate-level simulation passes
  with 16 valid NOP fetches through address 0x40 and 0 errors or warnings. The
  generic structural netlist is then identifier-sanitized without logic
  changes and compiled by Quartus into 1216 ALMs and 988 registers. Standard
  Fit passes 50 MHz timing with 0.244 ns worst setup slack, and JTAG programming
  of the physical FPGA passes. Physical reset behavior also passes: LEDR[9]
  turns off while KEY[0] is pressed and returns on when reset is released.
```

Manual GUI scratch projects should use a `*_gui_manual/` directory name. Those
directories are ignored because they contain generated Quartus build outputs.

## Snitch-Lite Track

The `D*` projects are DE1-SoC FPGA board bring-up projects. The `S*` projects
are the path toward a real Snitch core/cluster.

```text
S0: Verilator first
    Build a reduced real Snitch target and run a tiny bare-metal program.

S1: simulated MMIO
    Add a small MMIO register and make Snitch write it from software.
    Current S1 checks the MMIO-style store in the Verilator trace.

S2: Quartus wrapper
    Try to synthesize the reduced Snitch wrapper for the DE1-SoC FPGA.
    Current S2 first exports a Quartus project and runs analysis/elaboration.
    Verified status: project export passes; Quartus Lite analysis does not yet
    pass because real Snitch dependencies use advanced SystemVerilog features.

S2.1: translation experiment
    Try sv2v/yosys as a preprocessing route before Quartus.
    Verified status: useful tools installed, but full snitch_cluster_wrapper
    translation is high-friction and not recommended to continue.

S3: core-only probe
    Stop using snitch_cluster_wrapper for DE1-SoC.
    Instantiate the real snitch core directly with local shims and a tiny shell.
    Verified status: sv2v/yosys and Quartus full compile pass for the reduced
    core-only shell.

S4: board-visible MMIO
    Feed Snitch a tiny instruction ROM and connect its MMIO store to LEDR.

S5: generated software ROM
    Compile assembly into ROM contents instead of hardcoding instruction words
    in RTL.

S6: checked generated ROM
    Make the generated-ROM path safer and easier to reuse with different small
    assembly payloads.

S7: tiny RAM check
    Add a small local data RAM and make Snitch perform a store/load/compare
    sequence before reporting pass/fail on LEDs.

S8: JTAG host control
    Wrap the Snitch-Lite RAM check in host-visible control/status registers and
    use System Console over USB-Blaster/JTAG as the temporary host.

D3: HPS/Linux host control
    Prove the DE1-SoC ARM Linux side can control an FPGA MMIO accelerator
    through the lightweight HPS-to-FPGA bridge.
    Verified status: host-side build passes and produces `.sof`/`.rbf`; JTAG
    programming passes; ARM Linux reads/writes the FPGA MMIO registers and gets
    the expected result.

S9: HPS/Linux Snitch-Lite host control
    Replace D3's toy register accelerator with the S8 Snitch-Lite block while
    keeping the same ARM Linux and HPS lightweight bridge host path.
    Verified status: ARM Linux starts Snitch-Lite through the HPS bridge and
    reads back done/pass/result/RAM state from the Snitch payload.

S10: HPS/Linux Snitch-Lite host data input
    Add ARM-written input data registers and copy them into Snitch local RAM
    before start.
    Verified status: ARM Linux runs Snitch-Lite twice without reprogramming,
    passing different input values each time and reading the computed results.

S11: HPS/Linux Snitch-Lite payload loader
    Add ARM-written instruction-memory payload loading before start.
    Verified status: ARM Linux writes a 9-word RISC-V payload into FPGA
    instruction memory, runs it twice with different input data, and reads the
    expected Snitch-computed results.

S12: HPS/Linux Snitch-Lite file payload loader
    Split the ARM host executable from the RISC-V/Snitch payload image.
    Verified status: ARM Linux reads `/tmp/s12_payload.bin`, writes its 9
    instruction words into FPGA instruction memory, runs the payload twice, and
    reads the expected Snitch-computed results.

S13: HPS/Linux Snitch-Lite done IRQ
    Add an interrupt-producing done latch around the Snitch-Lite payload-loader
    wrapper and connect it to HPS f2h_irq0.
    Verified status: ARM Linux enables the done IRQ, runs the file-loaded
    payload twice, observes IRQ_PENDING/irq-line assertion after each run,
    clears the pending bit, and sees the irq line deassert. This now passes on
    the LXDE Ubuntu image after running the headless-prep step before JTAG
    programming.

    Current limitation: S13 verifies the FPGA/HPS interrupt path at hardware
    and MMIO level, but does not yet use a Linux kernel/UIO driver to sleep on
    the interrupt. S14 below closes that Linux-consumer gap.

S14: Linux IRQ consumer
    Reuse the S13 bitstream and consume f2h_irq0 from ARM Linux with a tiny
    matching kernel module.
    Verified status on the older console image: CONFIG_UIO is absent, so S14
    uses snitch_lite_irq.ko instead. Linux registers GIC IRQ 72, creates
    /dev/snitch_lite_irq, userspace blocks on the device, two Snitch-Lite
    completions wake userspace, IRQ 72 increments by two in /proc/interrupts,
    and TEST_RC=0. Verified status on the LXDE image: S14 builds a separate
    module against kernel 4.5.0-00183-g4647b69-dirty, maps Qsys f2h_irq0/GIC
    SPI 40 to Linux virtual IRQ 131, wakes userspace twice, increments IRQ 131
    by two in /proc/interrupts, and exits with TEST_RC=0.

S15: HPS/Linux Snitch-Lite payload metadata/header
    Reuse the S13 bitstream and replace the anonymous raw payload file with a
    structured S15 image.
    Verified status: ARM Linux validates magic/version/header size/entry
    word/payload word count/arguments/expected result/checksum, loads the
    payload words into FPGA instruction memory, runs Snitch-Lite, and observes
    the done IRQ pending/clear behavior with TEST_RC=0. This path now also
    passes on the LXDE Ubuntu serial-only image after the S13 headless-prepared
    bitstream is loaded.
```
