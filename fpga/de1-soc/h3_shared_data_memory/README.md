# H3: Shared Host/Snitch Data Memory

H3 adds a 4 KiB shared data RAM to the upstream Snitch heterogeneous path.
ARM Linux writes job inputs, uploads a RISC-V program, releases Snitch, blocks
on the completion interrupt, reasserts reset, and reads the computed outputs.

```text
ARM Linux                         Cyclone V fabric                     Snitch
    │                                   │                                │
    ├─ write program ──────────────────►│ boot RAM at 0x1000             │
    ├─ write inputs ───────────────────►│ shared RAM ◄───────────────────┤
    ├─ release reset                    │                                │
    │                                   │                     load/compute/store
    │                                   │                                │
    │◄──────────── completion IRQ ──────┤◄── signature store at 0x2000 ─┤
    ├─ reassert reset                   │                                │
    └─ read outputs ◄───────────────────│ shared RAM                     │
```

This is the first upstream-path milestone that exchanges a multiword payload
in both directions. H0.7 returned one signature register; H2 selected code;
H3 provides distinct instruction and job-data memories.

## Address Map

Offsets are relative to HPS lightweight bridge base `0xff200000`:

```text
Host physical range              Purpose
0xff200000-0xff200fff            control, status, result and IRQ
0xff201000-0xff201fff            4 KiB boot-program upload window
0xff202000-0xff202fff            4 KiB shared input/output data RAM
0xff203000 and above             forwarded cluster host window
```

The Snitch architectural addresses are:

```text
0x00001000-0x00001fff            boot RAM, instruction fetch
0x00002000                       completion signature sink
0x00004000-0x00004fff            shared data RAM, loads and stores
```

Control registers `DATA_BASE` and `DATA_SIZE` are exposed at local offsets
`0x24` and `0x28` and report `0x2000` and `4096` respectively.

## Ownership Protocol

The initial H3 contract deliberately avoids simultaneous host/Snitch access:

```text
CONTROL.bit0 = 0   Snitch held in reset; Linux may read/write shared RAM
CONTROL.bit0 = 1   Snitch running; Linux shared-window writes are ignored and
                   reads return zero
```

After the interrupt, Linux reasserts reset before reading output data. This is
a phase-owned shared memory, not coherent cacheable memory. It provides a safe
payload boundary without yet requiring arbitration or cache coherence.

## Hardware

[`rtl/axi_shared_data_ram.sv`](rtl/axi_shared_data_ram.sv) uses one explicit
Cyclone V `altsyncram`:

```text
Port A: 1024 x 32, host read/write, four byte enables
Port B:  512 x 64, Snitch narrow AXI read/write, eight byte enables
Storage: 4 M10Ks, 32,768 bits
Mode:    true dual port, single clock
```

The same AXI responder retains the H0.7 completion store at `0x2000`, so H1's
interrupt contract remains unchanged. Reads and writes outside the shared RAM
or completion address return AXI `DECERR`.

Cyclone M10K registers its read address even with an unregistered data output.
The ARM-side Avalon control therefore inserts one wait cycle for shared-data
reads. Without it, Linux observes the previously addressed word.

## Test Program

[`firmware/shared_transform.S`](firmware/shared_transform.S) processes four
32-bit words:

```text
output[i] = input[i] * 3 + 7
```

Inputs start at Snitch `0x4000`, outputs at `0x4040`, and the program writes
`0x4833` to `0x2000` after all output stores complete.

## Reproduce

```bash
./scripts/test_shared_data_ram.sh
./scripts/build_firmware.sh

cd ../h0_5_safe_host_control
./scripts/build.sh

cd ../h3_shared_data_memory
BOARD_SUDO_PASSWORD=temppwd ./scripts/run_board_test.sh
```

The unit test checks host byte enables, host readback, AXI reads and writes,
IDs, responses, completion capture, and out-of-range errors. The board script
builds and uploads the RISC-V binary, writes input words, waits through the H1
Linux IRQ driver, and validates every output word.

## Build Result

Verified with Quartus Prime Lite 25.1 on 2026-07-13:

```text
Logic utilization:         10,392 / 32,070 ALMs (32%)
Registers:                 7,755
M10K blocks:               32 / 397 (8%)
Shared RAM implementation: 4 M10Ks / 32,768 bits
Worst setup slack:         +17.445 ns
Worst hold slack:          +0.143 ns
SOF and RBF:               generated
```

## Physical Result

Verified on the DE1-SoC LXDE Linux image on 2026-07-13:

```text
H3_IRQ_READER_WOKE
COMPLETION_SIGNATURE=0x4833
OUTPUT0=0x10
OUTPUT1=0x1C
OUTPUT2=0x37
OUTPUT3=0x307
H3_SHARED_DATA_PASS
```

The inputs were `3`, `7`, `16`, and `256`; all four outputs match
`3 * input + 7`. The proof traverses the ARM lightweight bridge, shared M10K
port A, upstream Snitch narrow AXI port, and the FPGA-to-HPS interrupt path.

## Bring-Up Findings

Two integration failures were found and corrected:

1. The SDC assumed exactly six imported loop-cut cells. H3 optimization removed
   one, so the constraint now accepts and constrains the five or six known
   active cuts while still failing outside that range.
2. The first board run computed correct data but Linux read the previous RAM
   address because M10K address capture takes a clock. A one-cycle Avalon
   wait-state fixed host reads.

The next logical milestone is H4: replace the debug-oriented `devmem2` command
sequence with one Linux host program and a small, explicit job descriptor ABI.
