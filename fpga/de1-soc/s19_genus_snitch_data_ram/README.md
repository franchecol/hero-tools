# S19: Genus Snitch Core Uses Local Data RAM

S19 extends the S17/S18 external-synthesis path with the missing load-response
channel. The real upstream Snitch integer core can now store a word in local
FPGA RAM, load it back, compare it in software, and report PASS or FAIL through
MMIO.

```text
RV32E payload ROM
       │ instruction fetch
       ▼
Genus-generated upstream Snitch core
       │ request/response data port
       ├── 0x00001000..0x0000103f ──► 16-word local RAM
       └── 0x40000000             ──► LED MMIO register
```

## Software Test

[`sw/ram_check.S`](sw/ram_check.S) performs:

```text
store 0x000000a5 to RAM[0]
load RAM[0]
compare loaded value with 0x000000a5
write 0x1a5 to LED MMIO on PASS
write 0x05a to LED MMIO on FAIL
```

`LEDR[9]` is reserved for reset-released status. The expected physical PASS
vector is therefore:

```text
LEDR[9:0] = 0x3a5
```

## Why A New Genus Netlist Is Required

S17 and S18 tied the Snitch data response to `p_valid=0`. Stores remained
observable because they use the request channel, but loads could never return
data. [`lab/snitch_genus_mem_probe.sv`](lab/snitch_genus_mem_probe.sv) now
flattens both halves of the upstream protocol:

```text
request:  q_valid, q_ready, write, address, data, byte strobes
response: p_valid, p_ready, read data, error
```

The probe still instantiates the pinned upstream `snitch` module directly with
RV32E enabled and FPU, DMA, SSR, virtual memory, and debug disabled.

## Reproduce

Run Genus on the university server and retrieve the generic netlist:

```bash
./scripts/deploy_and_run_lab.sh
./scripts/fetch_netlist.sh
```

Validate the TSMC65 mapped netlist in Questa:

```bash
./scripts/run_gate_sim_lab.sh
```

Run the local structural simulation and compile for Cyclone V:

```bash
./scripts/run_sim.sh
./scripts/build.sh
```

Program the DE1-SoC over JTAG:

```bash
./scripts/program.sh
```

Generated software, netlists, simulation products, Quartus databases, and SOF
files are ignored. Captured evidence and checksums are recorded after each gate
passes.

The verified Genus generic netlist SHA-256 is:

```text
558f10a2df2b65d74f35532d985ad892e035d8873cd306b1f5c3de107807d882
```

## Verified Results

```text
Genus version:                 21.18-s082_1
Genus generic synthesis:      PASS
Genus TSMC65 mapping:         PASS
Mapped cells:                 3393
Mapped area:                  12817
Mapped netlist SHA-256:       7ddea4a260985157e29eac20aeb555711b60920e5dfb8366ab5c9e846f6bae9f

Questa mapped simulation:     PASS
Observed RAM[0]:              0x000000a5
Observed LEDR:                0x3a5
Questa errors/warnings:       0 / 0

Verilator generic simulation: PASS
Observed RAM[0]:              0x000000a5
Observed LEDR:                0x3a5

Quartus version:              25.1 Lite
Cyclone V fit:                PASS
Logic utilization:           670 / 32070 ALMs (2%)
Registers:                   817
Worst setup slack at 50 MHz: +4.160 ns
Worst hold slack:            +0.170 ns

JTAG target:                  5CSEMA5F31@2
SOF checksum:                 0x00CB5941
JTAG programming:             PASS, 0 errors / 0 warnings
Physical LEDR=0x3a5:         PASS
```

The 16-word RAM is intentionally small and Quartus implements it in logic
registers rather than an M10K block. A larger or explicitly inferred memory is
a later architectural step, not required for this protocol proof.

## Status

```text
RV32E software build:         PASS
Genus elaboration:            PASS
Genus generic synthesis:      PASS
Genus TSMC65 mapping:         PASS
Questa mapped simulation:     PASS
Verilator structural test:    PASS
Quartus Cyclone V compile:    PASS
JTAG programming:             PASS
Physical LED confirmation:    PASS
```

The user physically confirmed `LEDR[9:0] = 0x3a5`, including reset and
software re-execution behavior. This completes S19.
