# Local Occamy M3 Manual Replay

M3 is the live mailbox-runtime proof.

```text
M0: wake Snitch and receive an interrupt
M1: exchange and validate a shared-memory buffer
M2: run and numerically verify a runtime/DMA/floating-point kernel
M3: launch a device function through the OpenMP-style mailbox runtime
```

The canonical command is:

```bash
./scripts/bootstrap-local-occamy-m3.sh
```

This M3 is deliberately smaller than a complete compiler-to-runtime OpenMP
offload flow. It proves the live host/mailbox/device-runtime boundary in the
Verilator simulator.

## 1. What M3 Does

The host creates two shared words:

```text
args[0] = 0x12345678
args[1] = 0
```

It sends four mailbox words to the Snitch side:

```text
0x02                 start command
omp_mailbox_target   device function address
&args                argument address
0                    reserved word
```

The device mailbox manager calls the supplied function. The target performs:

```c
args[1] = args[0] + 1;
```

The device returns completion code `0x04`. The host accepts the run only when:

```text
completion == 0x04
args[1] == 0x12345679
```

## 2. Reproducibility Inputs

M3 inherits the M0 simulator pins:

```text
scripts/occamy-m0.lock.env
scripts/requirements-occamy-m0.txt
scripts/patches/occamy-m0-verilator.patch
```

M3 adds:

```text
scripts/occamy-m3.lock.env
```

The M3 lock records:

```text
input, output, and completion values
target-function size
LLVM and Snitch revisions
Clang version
device/runtime, host, and Snitch-runtime tree hashes
device binary hash
host loadable-image hash
```

## 3. Prepare The LLVM Device Toolchain

Initialize the pinned LLVM source:

```bash
git submodule update --init toolchain/llvm-project
```

If the RV32 compiler or sysroot is absent:

```bash
source scripts/setenv.sh
make hero-tc-llvm-axpy
```

Despite the target name, this produces the same generic HeroSDK RV32 LLVM
toolchain and `rv32imafd-ilp32d` sysroot used by M2 and M3.

The pinned LLVM revision is:

```text
511b80b732ec818619bfbefeab6011bd384dac0a
```

## 4. Build The Reduced Simulator

Generate the single-cluster headers:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  all-headers
```

Build or reuse the lean Verilator simulator:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  VLT='verilator --timing -DASSERTS_OFF' \
  VLT_JOBS=1 \
  VLT_TRACE=0 \
  VLT_PROF=0 \
  VLT_OUTPUT_SPLIT=5000 \
  VLT_OUTPUT_SPLIT_CFUNCS=5000 \
  bin/occamy_top.vlt
```

## 5. Build Device Support Libraries

```bash
make -C platforms/occamy/target/sim/sw/device/runtime all
make -C platforms/occamy/target/sim/sw/device/math all
```

The M3 device application also links `libomptarget_device`, which contains the
mailbox manager that receives the launch words and calls the target function.

## 6. Build The Partial Host ELF

```bash
make -C platforms/occamy/target/sim/sw/host/apps/omp_mailbox clean
make -C platforms/occamy/target/sim/sw/host/apps/omp_mailbox partial-build
```

The partial ELF provides an initial `snitch_main` address. The device image must
be linked at that address because the final host ELF embeds it there.

## 7. Build The Device Payload

```bash
make -C platforms/occamy/target/sim/sw/device/apps/omp_mailbox clean
make -C platforms/occamy/target/sim/sw/device/apps/omp_mailbox all
```

Expected artifacts:

```text
omp_mailbox.elf
omp_mailbox.bin
omp_mailbox.dump
omp_mailbox.dwarf
```

The ELF contains both:

```text
the mailbox runtime entry point
the 16-byte omp_mailbox_target function
```

## 8. Finalize The Host ELF

Read the target address:

```bash
install/bin/llvm-nm -n \
  platforms/occamy/target/sim/sw/device/apps/omp_mailbox/build/omp_mailbox.elf |
  grep ' omp_mailbox_target$'
```

Pass it into the final host link:

```bash
make -C platforms/occamy/target/sim/sw/host/apps/omp_mailbox \
  finalize-build DEVICE_TARGET_FN=0xADDRESS
```

The host source stores this address in its launch packet. Replace
`0xADDRESS` with the value printed by `llvm-nm`.

The final link can move `snitch_main`. If it differs from the partial address,
write the new address to:

```text
platforms/occamy/target/sim/sw/device/apps/omp_mailbox/build/origin.ld
```

using:

```text
L3_ORIGIN = 0xNEW_ADDRESS;
```

Then rebuild the device and finalize the host again. The runner repeats this
process for up to three passes until the embedded-device address is stable.

## 9. Run The Simulation

```bash
cd platforms/occamy/target/sim
./bin/occamy_top.vlt \
  sw/host/apps/omp_mailbox/build/omp_mailbox.elf
cd -
```

The simulator produces:

```text
platforms/occamy/target/sim/trace_hart_00.dasm
platforms/occamy/target/sim/logs/trace_hart_00001.dasm
```

## 10. What The Runner Verifies

The deterministic M3 runner checks:

```text
source trees match the pinned hashes
LLVM, Snitch, and Clang match the pinned versions
omp_mailbox_target is exactly 16 bytes
device and host loadable bytes match their pinned hashes
device trace enters omp_mailbox_target
target stores 0x12345679 into args[1]
device writes completion code 0x04 into the A2H mailbox
host loads and validates args[1]
host does not enter the bad-completion return path
host reaches its tohost exit
```

Addresses are derived from the newly built ELF files. They are not copied from
one old simulation trace.

## 11. Normal Reproduction

Use:

```bash
./scripts/bootstrap-local-occamy-m3.sh
```

For a deliberate unverified tool/version experiment:

```bash
M0_STRICT_VERSIONS=0 M0_ALLOW_UNPINNED=1 \
  ./scripts/bootstrap-local-occamy-m3.sh
```

That is not the pinned M3 path.
