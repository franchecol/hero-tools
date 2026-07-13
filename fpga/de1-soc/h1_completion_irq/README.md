# H1: Upstream Completion Interrupt

H1 turns the H0.7 result event into a level-high FPGA-to-HPS interrupt. ARM
Linux can now sleep in a blocking driver read instead of polling STATUS.

```text
Snitch store to 0x2000
  │
  ▼
H0.7 signature sink: result_valid
  │ rising event
  ▼
H1 pending latch ── AND IRQ_ENABLE ──► Qsys f2h_irq0
                                           │
                                           ▼
                                  Cyclone V GIC SPI 40
                                           │
                                           ▼
                                Linux IRQ 131 in this boot
                                           │
                                           ▼
                                /dev/snitch_lite_irq read()
```

## Hardware Contract

Offsets are relative to the HPS lightweight bridge base `0xff200000`:

```text
0x04  CONTROL      bit0 releases Snitch reset
0x10  BOOT_RESULT  result written by Snitch
0x14  IRQ_ENABLE   bit0 enables the HPS interrupt
0x18  IRQ_PENDING  bit0 pending, bit1 enabled, bit2 line asserted
```

`IRQ_PENDING.bit0` is set only on the rising edge of H0.7 `result_valid`.
Writing one to bit 0 acknowledges the event. This matters because the result
itself remains valid until Snitch reset is reasserted; acknowledgement must not
immediately retrigger the level interrupt.

The Qsys system enables `F2SINTERRUPT` and connects the component interrupt
sender to `hps_0.f2h_irq0`. On Cyclone V this input is GIC SPI 40, hardware IRQ
72. The Linux virtual IRQ number is allocated dynamically and was 131 during
the recorded LXDE test.

## Reused Linux Boundary

H1 reuses the SL14 `snitch_lite_irq` driver rather than copying it. Despite its
historical name, the driver accepts the MMIO base and pending-register offset
as module parameters. H1 supplies `irq_pending_offset=0x18`; SL14 used `0x3c`.
The driver reads the pending state, writes one to acknowledge it, records an
event, and wakes processes blocked on `/dev/snitch_lite_irq`.

```bash
BOARD_SUDO_PASSWORD=temppwd ./scripts/run_board_test.sh
```

The script rebuilds the driver for the LXDE kernel, transfers it over UART,
loads it with `gic_spi=40`, uploads the H0.7 program when running on H2 or
later, starts a blocking eight-byte read, and only then releases Snitch reset.

## Build Result

```text
Control simulation:      H1_IRQ_CONTROL_PASS
Qsys generation:         PASS, 23 modules / 86 files
Quartus map/fit:          PASS
Logic utilization:       10,509 / 32,070 ALMs (33%)
Registers:               7,670
M10K blocks:             24 / 397 (6%)
Worst setup slack:       +18.786 ns
Worst hold slack:        +0.133 ns
SOF and RBF:             generated
```

## Physical Result

Verified on the DE1-SoC LXDE Linux image on 2026-07-12:

```text
IRQ_READER_WOKE
event count              = 0x00000001
event IRQ status         = 0x00000007
STATUS after wake        = 0x0000001e
BOOT_RESULT after wake   = 0x000005a5
IRQ_PENDING after ack    = 0x00000002
/proc/interrupts count   = 1
Linux IRQ / GIC hwirq    = 131 / 72
H1_IRQ_WAKE_PASS
```

Event status `0x7` proves pending, enabled, and asserted were all visible to
the interrupt handler. The post-handler value `0x2` proves that the driver
acknowledged pending and deasserted the line while leaving IRQ enable set.
