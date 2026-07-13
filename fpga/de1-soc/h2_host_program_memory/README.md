# H2: Host-Selected Snitch Program Memory

H2 replaces the fixed instruction ROM with 4 KiB of host-writable Cyclone V
block RAM. ARM Linux uploads 32-bit RISC-V instructions while Snitch is held
in reset; Snitch fetches the same storage as 64-bit AXI beats at `0x1000`.

```text
ARM Linux writes 32-bit words                Snitch fetches 64-bit beats
              │                                           │
              ▼                                           ▼
host 0xff201000-0xff201fff ──► 4 KiB M10K boot RAM ◄── AXI 0x1000-0x1fff
```

Host writes are accepted only while `CONTROL.bit0=0`. The local map is:

```text
0x0000-0x0fff  control, status, result and IRQ registers
0x1000-0x1fff  write-only boot upload window
0x2000+        forwarded upstream cluster window
```

## Verification

```bash
./scripts/test_boot_ram.sh
BOARD_SUDO_PASSWORD=temppwd ./scripts/run_board_test.sh
```

The independent test covers 32-bit host writes, byte enables, 64-bit AXI
bursts, backpressure, IDs, RLAST, fetch observation and DECERR. The control
test verifies upload routing and rejects writes after reset release.

The board test builds two RISC-V binaries, uploads and runs the first,
reasserts reset, overwrites the same RAM with the second, and runs again
without rebuilding or reprogramming the FPGA between jobs.

## Build Result

```text
Logic utilization:       10,414 / 32,070 ALMs (32%)
Registers:               7,695
M10K blocks:             28 / 397 (7%)
Boot RAM implementation: 4 M10Ks / 32,768 bits
Worst setup slack:       +16.997 ns
Worst hold slack:        +0.130 ns
SOF and RBF:             generated
```

## Physical Result

Verified on 2026-07-12:

```text
PROGRAM0
STATUS=0x0000001e
PROGRAM0_RESULT=0x5A5

PROGRAM1
STATUS=0x0000001e
PROGRAM1_RESULT=0x3C3

H2_TWO_PROGRAMS_PASS
```

The FPGA image and Snitch hardware remained unchanged. Only the host-uploaded
instruction image changed, proving software selection of the accelerator
program through the real Snitch instruction and data paths.
