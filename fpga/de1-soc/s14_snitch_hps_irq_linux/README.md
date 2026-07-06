# Snitch-Lite S14: Linux IRQ Consumer Preflight

S14 continues after S13.

S13 proved that the FPGA side can produce and clear a done interrupt signal:

```text
Snitch payload writes done MMIO
  -> S13 wrapper sets IRQ_PENDING
  -> irq_line = IRQ_ENABLE && IRQ_PENDING
  -> Qsys connects irq_line to hps_0.f2h_irq0
  -> ARM Linux can observe pending/clear through MMIO
```

S14 is the next step: make Linux consume that FPGA-to-HPS interrupt for real.
That means the ARM program should block in Linux until the FPGA IRQ arrives,
instead of only polling MMIO.

## Current Result

S14 is currently a **preflight stage**, not a completed blocking IRQ driver.

The S13 hardware/runtime baseline was rerun on the local DE1-SoC board on
2026-07-06:

```text
JTAG chain:         DE-SoC [1-1], SOCVHPS + 5CSE device detected
S13 .sof program:   pass
S13 ARM runtime:    pass
S13 TEST_RC:        0
```

The board Linux IRQ preflight found:

```text
Kernel:
  Linux socfpga 3.12.0-00307-g507abb4-dirty

Userspace IRQ route:
  /dev/uio*:           not present
  CONFIG_UIO:          not set

Kernel module route:
  CONFIG_MODULES:      y
  CONFIG_MODULE_UNLOAD:y
  running kernel:      3.12.0-00307-g507abb4-dirty
  installed modules:   /lib/modules/3.9.0
  stale demo module:   /lib/modules/3.9.0/extra/gpio_interrupt.ko
  stale module load:   fails, invalid vermagic

Device tree:
  no custom Snitch-Lite/f2h_irq0 node is present in the running tree
```

So the easy UIO path is blocked on this SD-card image. The existing Terasic
`gpio_interrupt.ko` is also unusable because it was built for a different
kernel.

## Why S13 Is Not Enough

S13 checks this:

```text
read REG_IRQ_PENDING
  bit0 pending = 1
  bit1 enable  = 1
  bit2 irq     = 1
```

That proves the FPGA-side interrupt output is asserted.

S13 does **not** check this:

```text
Linux kernel IRQ handler wakes userspace
```

For that, Linux must have a driver or device-tree binding that registers the
FPGA IRQ line.

## S14 Target Behavior

The final S14 behavior should be:

```text
ARM Linux program
  -> mmap S13/S14 MMIO registers
  -> clear stale IRQ_PENDING
  -> enable IRQ_ENABLE
  -> load Snitch payload
  -> start Snitch
  -> block in Linux waiting for f2h_irq0
  -> wake when FPGA IRQ arrives
  -> clear IRQ_PENDING
  -> verify result/pass/RAM state
```

## Implementation Options

```text
┌────────┬───────────────────────────────┬────────────────────────────────────┐
│ Option │ Path                          │ Current status                     │
├────────┼───────────────────────────────┼────────────────────────────────────┤
│ A      │ UIO / generic-uio             │ blocked: CONFIG_UIO is not set     │
│ B      │ tiny custom kernel module     │ viable, but needs matching kernel  │
│ C      │ rebuild/replace Linux image   │ viable, heavier but cleanest       │
└────────┴───────────────────────────────┴────────────────────────────────────┘
```

Recommended next engineering route:

```text
1. Obtain or build the exact kernel source/build tree for:
     3.12.0-00307-g507abb4-dirty

2. Build one of:
     a. a tiny char/misc driver that request_irq()s f2h_irq0
     b. a kernel with CONFIG_UIO enabled plus a device-tree node

3. Add a device-tree node or module parameter that binds:
     MMIO base: 0xff200000
     MMIO size: 0x1000
     IRQ: f2h_irq0, irqNumber 0 from Qsys

4. Run the final blocking wait test.
```

## Files

```text
README.md
  This document and the current S14 decision record.

captures/s14_preflight_2026-07-06.txt
  Condensed live board evidence from the S14 preflight.

scripts/board_irq_preflight.py
  UART helper that logs into the board and prints IRQ/UIO/module/device-tree
  state needed before implementing the Linux IRQ consumer.
```

## Run The Preflight

Boot the board, program the S13 bitstream, ensure the ARM Linux console is
available on `/dev/ttyUSB0`, then run:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/s14_snitch_hps_irq_linux
./scripts/board_irq_preflight.py
```

Optional:

```bash
TTY=/dev/ttyUSB0 ./scripts/board_irq_preflight.py
```

The script does not modify the board. It only reads kernel/device state.

## What Would Count As S14 Complete

S14 should be considered complete only when all of these are true:

```text
Linux has a registered IRQ consumer for f2h_irq0.
Userspace blocks waiting for that interrupt.
Snitch completion wakes userspace without polling STATUS.done.
/proc/interrupts shows the relevant interrupt count incrementing.
The Snitch result/RAM/pass checks still match S13.
```

Until then, S14 is correctly documented as blocked by the current Linux image's
missing UIO support and missing matching kernel module build environment.
