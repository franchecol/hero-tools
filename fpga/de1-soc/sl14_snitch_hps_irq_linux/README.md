# Snitch-Lite SL14: Linux IRQ Consumer

SL14 continues after SL13.

SL13 proved that the FPGA side can produce and clear a done interrupt signal:

```text
Snitch payload writes done MMIO
  -> SL13 wrapper sets IRQ_PENDING
  -> irq_line = IRQ_ENABLE && IRQ_PENDING
  -> Qsys connects irq_line to hps_0.f2h_irq0
  -> ARM Linux can observe pending/clear through MMIO
```

SL14 makes Linux consume that FPGA-to-HPS interrupt for real. The ARM program
blocks in Linux until the FPGA IRQ arrives instead of only polling MMIO.

## Current Result

SL14 is complete on both tested local DE1-SoC Linux images:

```text
older console image:
  kernel: 3.12.0-00307-g507abb4-dirty
  IRQ path: direct Linux IRQ 72
  result: TEST_RC=0

LXDE Ubuntu image:
  kernel: 4.5.0-00183-g4647b69-dirty
  IRQ path: GIC SPI 40 -> Linux virtual IRQ 131
  result: TEST_RC=0
```

The console-image automated run was executed on the local DE1-SoC board on
2026-07-06 with kernel `3.12.0-00307-g507abb4-dirty`:

```text
SL13 .sof program:       pass
kernel module build:    pass
ARM waiter build:       pass
UART file transfer:     pass
insmod snitch_lite_irq: pass
blocking IRQ wait:      pass
SL14 TEST_RC:            0
```

The key evidence:

```text
Kernel:
  Linux socfpga 3.12.0-00307-g507abb4-dirty

Module:
  snitch_lite_irq.ko
  vermagic: 3.12.0-00307-g507abb4-dirty SMP mod_unload ARMv7 p2v8
  registered: /dev/snitch_lite_irq

Interrupt:
  Linux IRQ: 72
  owner:     snitch_lite_irq
  before:    72: 4
  after:     72: 6

Userspace:
  RUN0_IRQ_EVENT_COUNT = 1
  RUN1_IRQ_EVENT_COUNT = 2
  RUN0_IRQ_EVENT_STATUS = 0x7
  RUN1_IRQ_EVENT_STATUS = 0x7
  PASS
```

The original UIO route is still unavailable on the tested console SD-card
image:

```text
/dev/uio*:  not present
CONFIG_UIO: not set
```

The existing Terasic `gpio_interrupt.ko` is also unusable because it was built
for kernel 3.9.0 while the board runs 3.12.0. SL14 therefore uses a tiny custom
module built against a matching 3.12.0 kernel build tree.

LXDE image result:

```text
LXDE kernel:     4.5.0-00183-g4647b69-dirty
module vermagic: 4.5.0-00183-g4647b69-dirty SMP mod_unload ARMv7 p2v8
Qsys IRQ:        f2h_irq0, offset 40
driver mapping:  gic_spi=40
Linux IRQ:       131
/proc/interrupts before:
  131: 0 0 GIC-0 72 Level snitch_lite_irq
/proc/interrupts after:
  131: 2 0 GIC-0 72 Level snitch_lite_irq
SL14 TEST_RC:     0
```

Important: on the LXDE 4.5 kernel, `irq=72` is wrong. Linux IRQ 72 belongs to
`gpio-dwapb`, not f2h_irq0. The driver must request the interrupt through the
GIC device-tree mapping using `gic_spi=40`; Linux then allocates virtual IRQ
131.

## Why SL13 Is Not Enough

SL13 checks this:

```text
read REG_IRQ_PENDING
  bit0 pending = 1
  bit1 enable  = 1
  bit2 irq     = 1
```

That proves the FPGA-side interrupt output is asserted.

SL13 does **not** check this:

```text
Linux kernel IRQ handler wakes userspace
```

For that, Linux must have a driver or device-tree binding that registers the
FPGA IRQ line.

## SL14 Behavior

The final SL14 behavior is:

```text
ARM Linux program
  -> mmap SL13/SL14 MMIO registers
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
│ B      │ tiny custom kernel module     │ done: SL14 uses this path           │
│ C      │ rebuild/replace Linux image   │ viable, heavier, not needed now    │
└────────┴───────────────────────────────┴────────────────────────────────────┘
```

The implemented console-image route:

```text
1. Use the exact kernel source/build tree for:
     3.12.0-00307-g507abb4-dirty

2. Build a tiny misc driver:
     request_irq(72, ...)
     expose /dev/snitch_lite_irq
     wake blocking read()/poll() callers

3. Pass module parameters instead of editing the device tree:
     MMIO base: 0xff200000
     MMIO size: 0x1000
     IRQ:       72, f2h_irq0 bit 0 on this image
     pending:   0x3c, SL13 REG_IRQ_PENDING

4. Run the blocking wait test from ARM Linux.
```

## Files

```text
README.md
  This document and the current SL14 result.

captures/s14_preflight_2026-07-06.txt
  Condensed live board evidence from the SL14 preflight.

captures/s14_irq_wait_2026-07-06.txt
  Condensed live board evidence from the completed SL14 run.

captures/s14_irq_wait_lxde_2026-07-06.txt
  Condensed live board evidence from the completed SL14 LXDE run.

scripts/board_irq_preflight.py
  UART helper that logs into the board and prints IRQ/UIO/module/device-tree
  state.

scripts/build_kernel_module.sh
  Builds snitch_lite_irq.ko against the matching kernel build tree.
  Use `BOARD_KERNEL=console` for the 3.12 console image and
  `BOARD_KERNEL=lxde` for the 4.5 LXDE image.

scripts/build_arm_waiter.sh
  Builds the static no-libc ARM userspace waiter.

scripts/send_and_run.sh
  Transfers the module, waiter, and payload to the board, loads the module, and
  runs the blocking IRQ wait test.

scripts/program_and_run.sh
  Programs the SL13 bitstream first, then runs send_and_run.sh.

driver/snitch_lite_irq.c
  Minimal Linux misc driver for f2h_irq0/SL13 REG_IRQ_PENDING.

sw/s14_irq_wait_nolibc.c
  ARM Linux userspace test that blocks on /dev/snitch_lite_irq.
```

## Run SL14

Boot the board, ensure the ARM Linux console is available on `/dev/ttyUSB0`,
and keep the prepared kernel/module build inputs available.

Console image inputs:

```text
KERNEL_SRC:
  /home/ftv/builds/kernel-src/linux-socfpga-criticallink

TOOLCHAIN:
  /home/ftv/builds/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf
```

Console image run:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl14_snitch_hps_irq_linux
BOARD_KERNEL=console ./scripts/program_and_run.sh
```

LXDE image inputs:

```text
KERNEL_SRC:
  /home/ftv/builds/kernel-src/linux-socfpga-altera-4.5

TOOLCHAIN:
  /home/ftv/builds/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf
```

LXDE image run:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/sl14_snitch_hps_irq_linux

BOARD_KERNEL=lxde \
PREPARE_LXDE_HEADLESS=1 \
BOARD_USER=ubuntu \
BOARD_PASSWORD=temppwd \
BOARD_SUDO_PASSWORD=temppwd \
./scripts/program_and_run.sh
```

If the SL13 bitstream is already loaded and LXDE has already been moved to
serial-only/headless mode, the runtime-only LXDE check is:

```bash
BOARD_KERNEL=lxde \
BOARD_USER=ubuntu \
BOARD_PASSWORD=temppwd \
BOARD_SUDO_PASSWORD=temppwd \
./scripts/send_and_run.sh
```

Expected console evidence:

```text
insmod /tmp/snitch_lite_irq.ko irq=72 ...
snitch_lite_irq: irq=72 mmio=0xff200000 size=0x1000 pending=0x3c
/dev/snitch_lite_irq exists
RUN0_IRQ_EVENT_COUNT = 0x00000001
RUN1_IRQ_EVENT_COUNT = 0x00000002
PASS
TEST_RC=0
/proc/interrupts IRQ 72 increments by two
```

Expected LXDE evidence:

```text
insmod /tmp/snitch_lite_irq.ko gic_spi=40 ...
snitch_lite_irq: mapped GIC SPI 40 to Linux irq=131
snitch_lite_irq: irq=131 gic_spi=40 gic_hwirq=-1 mmio=0xff200000 size=0x1000 pending=0x3c
RUN0_IRQ_EVENT_COUNT = 0x00000001
RUN1_IRQ_EVENT_COUNT = 0x00000002
PASS
TEST_RC=0
/proc/interrupts IRQ 131 increments by two
```

## Completion Criteria

SL14 is considered complete because all of these are true:

```text
Linux has a registered IRQ consumer for f2h_irq0.
Userspace blocks waiting for that interrupt.
Snitch completion wakes userspace without polling STATUS.done.
/proc/interrupts shows the registered IRQ incrementing.
The Snitch result/RAM/pass checks still match SL13.
```
