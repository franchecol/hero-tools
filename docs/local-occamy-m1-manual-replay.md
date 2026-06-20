# Local Occamy M1 Manual Replay

M1 is the first shared-memory data-path proof after M0.

For the complete milestone progression, start with the
[Local Occamy Milestone Roadmap](local-occamy-roadmap.md).

```text
M0
  Host wakes Snitch.
  Snitch interrupts host.

M1
  Host initializes 16 words.
  Host gives Snitch the buffer address.
  Snitch increments every word.
  Snitch interrupts host.
  Host validates all 16 results and exits successfully.
```

The canonical entry point is:

```bash
./scripts/bootstrap-local-occamy-m1.sh
```

## 1. Reproducibility Inputs

M1 shares the pinned simulator environment with M0:

```text
scripts/occamy-m0.lock.env
scripts/requirements-occamy-m0.txt
scripts/patches/occamy-m0-verilator.patch
```

M1 adds a source-integrity manifest:

```text
scripts/occamy-m1.lock.env
```

That file records the number of words and SHA-256 hashes of:

```text
device roundtrip Makefile
device roundtrip.S
host roundtrip Makefile
host roundtrip.c
```

The pinned Occamy revision remains:

```text
2ffef40126b5deb2bc14ec4c9a2ed0fa94b9a6c3
```

## 2. Enter The Repository

```bash
HERO_TOOLS_ROOT=/path/to/hero-tools
cd "${HERO_TOOLS_ROOT}"
```

Check the M1 inputs:

```bash
test -x scripts/bootstrap-local-occamy-m1.sh
test -f scripts/occamy-m1.lock.env
test -f platforms/occamy/target/sim/sw/device/apps/roundtrip/Makefile
test -f platforms/occamy/target/sim/sw/device/apps/roundtrip/src/roundtrip.S
test -f platforms/occamy/target/sim/sw/host/apps/roundtrip/Makefile
test -f platforms/occamy/target/sim/sw/host/apps/roundtrip/src/roundtrip.c
```

## 3. Verify The Pinned Environment

M1 uses the same checks as M0:

```text
Python 3.14.5
Bender 0.31.0
Verilator 5.048
host GCC 16.1.1
RISC-V GCC 15.2.0
single-cluster Occamy configuration
```

The bootstrap also verifies the M1 source hashes before building. A local edit
to one of the four roundtrip files therefore stops the pinned run instead of
silently producing a different proof.

## 4. Build The Shared Simulator

Generate the single-cluster files:

```bash
make -C platforms/occamy/target/sim \
  CFG_OVERRIDE=cfg/single-cluster.hjson \
  VERIBLE_FMT=true \
  all-headers
```

Build or reuse the lean simulator:

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
  CC=cc \
  CXX=c++ \
  CXXFLAGS='-include cstdint -fcoroutines' \
  bin/occamy_top.vlt
```

M0 and M1 use the same hardware model, so a matching M0-built simulator can be
reused.

## 5. Build The M1 Device Payload

```bash
make -C platforms/occamy/target/sim/sw/device/apps/roundtrip clean
make -C platforms/occamy/target/sim/sw/device/apps/roundtrip all
```

Artifacts:

```text
roundtrip.elf
  Device symbols and disassembly.

roundtrip.bin
  Raw Snitch payload embedded into the host ELF.
```

The device algorithm is:

```text
read hart ID
only hart 1 continues
read the communication-buffer pointer
read usr_data_ptr
repeat 16 times:
  load one word
  add 1
  store the result
raise the host software interrupt
park
```

## 6. Build The M1 Host

```bash
make -C platforms/occamy/target/sim/sw/host/apps/roundtrip clean
make -C platforms/occamy/target/sim/sw/host/apps/roundtrip finalize-build
```

Artifact:

```text
platforms/occamy/target/sim/sw/host/apps/roundtrip/build/roundtrip.elf
```

The host algorithm is:

```text
write 0 through 15 into roundtrip_buffer
put roundtrip_buffer in comm_buffer.usr_data_ptr
bring Snitch online
wake Snitch
wait for the completion interrupt
validate that the words are now 1 through 16
return 0 on success, 1 on failure
```

## 7. Run M1

```bash
cd platforms/occamy/target/sim
./bin/occamy_top.vlt sw/host/apps/roundtrip/build/roundtrip.elf
cd "${HERO_TOOLS_ROOT}"
```

The simulator receives only the host ELF because `roundtrip.bin` is already
embedded at the `snitch_main` symbol.

## 8. What Verification Proves

The runner derives all relevant addresses from the generated ELFs. It does not
store fixed program-counter values.

For each word `i` from 0 through 15, it requires a device trace event equivalent
to:

```text
address = roundtrip_buffer + i * 4
stored value = i + 1
```

It then requires:

```text
Snitch completion interrupt store
host interrupt-clear store
host tohost exit store
```

It also rejects any trace that enters the host's `return 1` validation-failure
path.

This is stronger than checking only that the simulation terminated: it proves
the complete 16-word shared-memory transformation and successful host
validation.

## 9. Complete Reproduction

The normal reproducible command is:

```bash
./scripts/bootstrap-local-occamy-m1.sh
```

The equivalent shared runner command is:

```bash
./scripts/bootstrap-local-occamy-minimal.sh roundtrip
```

The dedicated M1 entry point is preferred because it cannot accidentally select
another mode.

For an intentional compatibility experiment:

```bash
M0_STRICT_VERSIONS=0 M0_ALLOW_UNPINNED=1 \
  ./scripts/bootstrap-local-occamy-m1.sh
```

That is not the pinned M1 path.
