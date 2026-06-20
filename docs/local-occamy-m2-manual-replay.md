# Local Occamy M2 Manual Replay

M2 is the reduced runtime-shaped AXPY proof.

For the complete milestone progression, start with the
[Local Occamy Milestone Roadmap](local-occamy-roadmap.md).

```text
M0: wake Snitch and receive an interrupt
M1: exchange and validate a small shared-memory buffer
M2: run a Snitch runtime/DMA/floating-point kernel and verify its output
```

The canonical command is:

```bash
./scripts/bootstrap-local-occamy-m2.sh
```

## 1. What M2 Computes

M2 computes 24 double-precision values:

```text
z[i] = a * x[i] + y[i]
```

The device payload uses:

```text
Snitch runtime startup
DMA copies between remote memory and cluster TCDM
cluster barriers
floating-point AXPY computation
DMA copy back to remote z
host completion interrupt
```

## 2. Reproducibility Inputs

M2 inherits the M0 simulator pins:

```text
scripts/occamy-m0.lock.env
scripts/requirements-occamy-m0.txt
scripts/patches/occamy-m0-verilator.patch
```

M2 adds:

```text
scripts/occamy-m2.lock.env
```

The M2 lock records:

```text
vector length: 24
NumPy seed: 0
relative error threshold: 1e-10
deterministic generated data.h hash
device binary hash
host loadable-image hash
LLVM source commit
Snitch source commit
Clang version
aggregate source-tree hashes
```

## 3. LLVM Device Toolchain

M2 needs the HeroSDK RV32 LLVM toolchain and the `rv32imafd-ilp32d` sysroot.

The dedicated bootstrap initializes the pinned LLVM submodule:

```bash
git submodule update --init toolchain/llvm-project
```

If the toolchain is absent, it runs:

```bash
source scripts/setenv.sh
make hero-tc-llvm-axpy
```

The verified LLVM revision is:

```text
511b80b732ec818619bfbefeab6011bd384dac0a
```

The verified compiler identifies itself as:

```text
clang version 15.0.0
```

## 4. Shared Occamy Simulator

M2 uses the same reduced single-cluster simulator as M0 and M1:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  all-headers
```

The lean Verilator configuration remains:

```text
VLT_JOBS=1
VLT_TRACE=0
VLT_PROF=0
VLT_OUTPUT_SPLIT=5000
VLT_OUTPUT_SPLIT_CFUNCS=5000
```

A compatible existing `occamy_top.vlt` is reused.

## 5. Deterministic Input Generation

The original Snitch `datagen.py` uses NumPy randomness. M2 executes that pinned
script in-process after setting:

```python
np.random.seed(0)
```

It requests:

```text
length = 24
section = empty
```

The resulting `data.h` must have SHA-256:

```text
9e271fb66075e34acb7682a6a0421db1903a29a524b15b03792323fb053da9e8
```

This means every clean M2 build uses exactly the same `a`, `x`, and `y`.

## 6. Build Runtime And Math Libraries

```bash
make -C platforms/occamy/target/sim/sw/device/runtime all
make -C platforms/occamy/target/sim/sw/device/math all
```

These provide the Occamy/Snitch startup, DMA, barriers, and math support linked
into the device ELF.

## 7. Build The Partial Host ELF

```bash
make -C platforms/occamy/target/sim/sw/host/apps/offload clean
make -C platforms/occamy/target/sim/sw/host/apps/offload \
  partial-build DEVICE_APPS=blas/axpy
```

The partial host link determines the final address where the device payload
will be embedded and writes it to the device `origin.ld`.

## 8. Build The Device AXPY Payload

```bash
make -C platforms/occamy/target/sim/sw/device/apps/blas/axpy all
```

Expected artifacts:

```text
axpy.elf
axpy.bin
axpy.dump
axpy.dwarf
```

The runner checks the ELF contract:

```text
l: 4 bytes
a: 8 bytes
x: 24 doubles = 192 bytes
y: 24 doubles = 192 bytes
z: 24 doubles = 192 bytes
```

It also checks that the raw device binary is byte-identical to the verified M2
payload.

## 9. Finalize The Host ELF

```bash
make -C platforms/occamy/target/sim/sw/host/apps/offload \
  finalize-build DEVICE_APPS=blas/axpy
```

The resulting simulator input is:

```text
platforms/occamy/target/sim/sw/host/apps/offload/build/offload-axpy.elf
```

The raw `axpy.bin` is embedded inside this host ELF at `snitch_main`.

GNU linker symbol/string-table ordering can vary between links, so M2 does not
hash the complete host ELF container. It converts the ELF to its loadable binary
image and verifies those executable bytes instead. The verified loadable image
hash is:

```text
54080307aedcd06c6989d70ead1c2101dbd71790c7ba007b3a70b77e041b13bc
```

## 10. Numerical Verification

M2 runs the pinned Snitch verification harness:

```bash
python platforms/occamy/deps/snitch_cluster/sw/blas/axpy/verify.py \
  --symbols-bin platforms/occamy/target/sim/sw/device/apps/blas/axpy/build/axpy.elf \
  platforms/occamy/target/sim/bin/occamy_top.vlt \
  platforms/occamy/target/sim/sw/host/apps/offload/build/offload-axpy.elf
```

The harness:

```text
runs the Occamy simulator
waits for the output z region
reads 192 bytes from simulated memory
extracts a, x, and y from axpy.elf
computes z_golden = a*x + y
compares all 24 simulated doubles to z_golden
fails if any relative error exceeds 1e-10
```

This proves numerical output, not merely program termination.

## 11. Normal Reproduction

Use:

```bash
./scripts/bootstrap-local-occamy-m2.sh
```

For a deliberate unverified tool/version experiment:

```bash
M0_STRICT_VERSIONS=0 M0_ALLOW_UNPINNED=1 \
  ./scripts/bootstrap-local-occamy-m2.sh
```

That is not the pinned M2 path.
