# Local Occamy M4 FPGA Bring-Up Plan

This is the M4 handoff from the local M3a/M3b software and simulation proofs to
a small FPGA proof. It intentionally does not claim that the qemu/Verilator
bridge is a real platform endpoint.

Start with the [Local Occamy Milestone Roadmap](local-occamy-roadmap.md).
For the complete M3b freeze and local reproduction guide, read the
[M3b OpenMP Replay Freeze](local-occamy-m3b-openmp-freeze.md).

## Current Baseline

Use the current branch baseline as the pre-FPGA regression point:

```text
M3b baseline:
  HeroSDK OpenMP cva6/occamy software stack builds.
  offload_benchmark_occamy.elf contains a RISC-V Linux host image plus an RV32
  Occamy target image.
  qemu-riscv64 reaches the Occamy OpenMP target plugin.
  all 16 captured OpenMP target launches replay through the real Snitch-side
  mailbox manager in Occamy Verilator.
  scripts/run-local-occamy-openmp-replay-bridge.sh --all gates the qemu host on
  Verilator replay success for all 16 launches.
  the five map(tofrom) launches receive replay-derived W32 copyback updates.
  the full bridge run completes without "Error: map to_from did not work".
```

The M3b baseline command is:

```bash
./scripts/run-local-occamy-openmp-replay-bridge.sh --all
```

Expected local evidence:

```text
output/occamy-openmp-bridge/responses/response-0004.status
output/occamy-openmp-bridge/responses/response-0007.status
output/occamy-openmp-bridge/responses/response-0010.status
output/occamy-openmp-bridge/responses/response-0013.status
output/occamy-openmp-bridge/responses/response-0016.status

Each contains:
  W32 0xc08003a0 0x0000000a

output/occamy-openmp-smoke.log contains no:
  Error: map to_from did not work
```

If this baseline is stale or missing on a new machine, rebuild M3a with
`./scripts/bootstrap-local-occamy-m3.sh`, then rebuild M3b using the commands in
the [M3b runbook](local-occamy-m3b-openmp-freeze.md) before spending FPGA build
time.

## Scope Boundary

Do not keep expanding the qemu/Verilator bridge unless simulator
infrastructure itself becomes the goal.

The useful next experiment is FPGA bring-up because the remaining risks are
platform-endpoint risks:

```text
/dev/occamydev--1 creation
Linux kernel module probe
device-tree address mapping
MMIO region mapping
mailbox synchronization
Snitch reset/wakeup
host/device memory visibility
OpenMP map(tofrom) copyback without trace-derived writes
```

## Target Platform Path

The checked-in FPGA path is VCU128-specific:

```text
platforms/occamy/target/fpga/
```

Important files:

```text
platforms/occamy/target/fpga/README.md
platforms/occamy/target/fpga/Makefile
platforms/occamy/target/fpga/occamy_vcu128.tcl
platforms/occamy/target/fpga/occamy_vcu128_program.tcl
platforms/occamy/target/fpga/occamy_vcu128_flash.tcl
platforms/occamy/target/fpga/occamy_vcu128_flashrun.tcl
platforms/occamy/target/fpga/bootrom/Makefile
platforms/occamy/target/fpga/bootrom/occamy_pcie.dts
sw/hero-driver/occamy/Makefile
sw/hero-driver/occamy/occamy_driver.c
sw/hero-driver/occamy/occamy_fops.c
cva6-sdk/rootfs/etc/init.d/S1driver
```

The repo flow names Xilinx VCU128 and Vivado/Vitis 2020.2.  The primary FPGA
make targets are:

```bash
cd platforms/occamy/target/fpga
make occamy_vcu128 EXT_JTAG=0 DEBUG=0
make program VCU=<01-or-02>
make flash-u-boot VCU=<01-or-02> UBOOT_ITB=<path-to-u-boot.itb>
make flash-uimage VCU=<01-or-02> LINUX_UIMAGE=<path-to-uImage>
```

The local reduced simulation has used a single-cluster Occamy configuration.
Before spending FPGA build time, confirm the FPGA RTL is reduced similarly
enough for VCU128.  The upstream FPGA README points to reducing
`nr_s1_quadrant` and `nr_clusters` to `1` before `make update-sources`; verify
the exact config location in the current Occamy checkout before editing.

## Pre-FPGA Software Probe

The smallest first FPGA application is:

```text
apps/omp/basic/map_tofrom_u32
```

It tests only one thing:

```c
uint32_t tmp_1 = 5;
uint32_t tmp_2 = 10;

#pragma omp target device(1) map(tofrom : tmp_1, tmp_2)
{
    tmp_1 = tmp_2;
}
```

Expected user-visible output on a working platform:

```text
PASS map_tofrom_u32: tmp_1=10 tmp_2=10
```

Build it from a configured HeroSDK shell:

```bash
cd /path/to/hero-tools
source scripts/setenv.sh
make HERO_HOST=cva6 HERO_DEVICE=occamy hero-sw-all
make -C platforms/occamy/target/sim/sw/device/apps/libomptarget_device all
make -C apps/omp/basic/map_tofrom_u32 DEVICES=occamy
```

The expected ELF is:

```text
apps/omp/basic/map_tofrom_u32/map_tofrom_u32_occamy.elf
```

## FPGA Bring-Up Milestones

M4.0: board and image sanity

```text
VCU128 visible to Vivado hardware server.
Bitstream programs successfully.
UART shows Occamy bootrom output.
U-Boot/OpenSBI/Linux boot far enough to get a shell or scripted init.
```

M4.1: driver endpoint

```text
occamy.ko is present in the rootfs.
insmod occamy.ko succeeds.
/dev/occamydev--1 appears.
dmesg shows the eth-occamy platform driver probe.
the mapped regions match the expected device tree addresses.
```

M4.2: HeroSDK host runtime endpoint

```text
map_tofrom_u32_occamy.elf starts on Linux.
libomptarget.rtl.herodev_occamy.so loads.
__tgt_rtl_init_device(1) succeeds.
the first OpenMP target region is launched.
```

M4.3: smallest correctness proof

```text
map_tofrom_u32_occamy.elf prints:
  PASS map_tofrom_u32: tmp_1=10 tmp_2=10

No fake driver, no replay bridge, no trace-derived W32 copyback.
```

M4.4: move back to benchmark

```text
offload_benchmark_occamy.elf runs.
No "Error: map to_from did not work" messages.
Device cycle counters are printed.
```

## Stop Conditions

Stop and debug the platform before larger benchmarks if any of these happen:

```text
/dev/occamydev--1 is missing.
occamy.ko probe fails.
LibHero mmap/ioctl calls fail.
Snitch wakeup hangs.
MBOX_DEVICE_DONE never returns.
map_tofrom_u32 prints FAIL.
```

Do not start with AXPY or matrix-vector.  They add workload complexity before
the platform endpoint has proven the basic OpenMP target contract.
