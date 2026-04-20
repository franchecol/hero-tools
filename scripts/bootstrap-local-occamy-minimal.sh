#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
OCCAMY_DIR="${ROOT_DIR}/platforms/occamy"
OCCAMY_URL="${OCCAMY_URL:-https://github.com/pulp-platform/occamy.git}"
OCCAMY_BRANCH="${OCCAMY_BRANCH:-ck/fpga2}"
RUNNER="${ROOT_DIR}/scripts/run-local-occamy-minimal.sh"
SIM_MAKEFILE="${OCCAMY_DIR}/target/sim/Makefile"
DEVICE_APP_DIR="${OCCAMY_DIR}/target/sim/sw/device/apps/minimal_irq"
ROUNDTRIP_DEVICE_APP_DIR="${OCCAMY_DIR}/target/sim/sw/device/apps/roundtrip"
ROUNDTRIP_HOST_APP_DIR="${OCCAMY_DIR}/target/sim/sw/host/apps/roundtrip"

log() {
  printf '[occamy-bootstrap] %s\n' "$*"
}

die() {
  printf '[occamy-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

ensure_checkout() {
  [[ -d "${ROOT_DIR}/.git" ]] || \
    die "bootstrap must run from a hero-tools checkout"
  [[ -x "${RUNNER}" ]] || \
    die "missing runner script: ${RUNNER}"
}

ensure_occamy_checkout() {
  local origin
  local branch

  mkdir -p "${ROOT_DIR}/platforms"

  if [[ ! -d "${OCCAMY_DIR}/.git" ]]; then
    log "cloning Occamy (${OCCAMY_BRANCH}) into ${OCCAMY_DIR}"
    git clone --branch "${OCCAMY_BRANCH}" --single-branch "${OCCAMY_URL}" "${OCCAMY_DIR}"
    return
  fi

  origin=$(git -C "${OCCAMY_DIR}" remote get-url origin 2>/dev/null || true)
  [[ -n "${origin}" ]] || die "existing ${OCCAMY_DIR} checkout has no origin remote"
  case "${origin}" in
    "${OCCAMY_URL}"|git@github.com:pulp-platform/occamy.git)
      ;;
    *)
      die "existing ${OCCAMY_DIR} checkout points to unexpected origin: ${origin}"
      ;;
  esac

  branch=$(git -C "${OCCAMY_DIR}" branch --show-current || true)
  [[ "${branch}" == "${OCCAMY_BRANCH}" ]] || \
    die "existing ${OCCAMY_DIR} checkout is on '${branch:-detached}', expected '${OCCAMY_BRANCH}'"
}

ensure_verilator_patch() {
  [[ -f "${SIM_MAKEFILE}" ]] || die "missing simulator Makefile: ${SIM_MAKEFILE}"

  if grep -q 'verilated_timing.o' "${SIM_MAKEFILE}" && \
     grep -q 'verilated_threads.o' "${SIM_MAKEFILE}"; then
    return
  fi

  log "applying local Verilator compatibility patch"
  python - "${SIM_MAKEFILE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "VLT_COBJ += $(VLT_BUILDDIR)/vlt/verilated_vcd_c.o\n"
replacement = (
    "VLT_COBJ += $(VLT_BUILDDIR)/vlt/verilated_vcd_c.o\n"
    "VLT_COBJ += $(VLT_BUILDDIR)/vlt/verilated_timing.o\n"
    "VLT_COBJ += $(VLT_BUILDDIR)/vlt/verilated_threads.o\n"
)
if "verilated_timing.o" in text and "verilated_threads.o" in text:
    sys.exit(0)
if needle not in text:
    raise SystemExit(f"cannot find Verilator object list anchor in {path}")
path.write_text(text.replace(needle, replacement, 1))
PY
}

ensure_minimal_payload() {
  local src_dir="${DEVICE_APP_DIR}/src"

  mkdir -p "${src_dir}"

  if [[ ! -f "${DEVICE_APP_DIR}/Makefile" ]]; then
    log "creating minimal_irq device app"
    cat > "${DEVICE_APP_DIR}/Makefile" <<'EOF'
# Copyright 2026

APP                := minimal_irq
BUILDDIR           := $(abspath build)
SRC                := $(abspath src/$(APP).S)
RISCV_CC           ?= riscv64-unknown-elf-gcc
RISCV_OBJCOPY      ?= riscv64-unknown-elf-objcopy
RISCV_OBJDUMP      ?= riscv64-unknown-elf-objdump
RISCV_CFLAGS       += -march=rv32im_zicsr
RISCV_CFLAGS       += -mabi=ilp32
RISCV_CFLAGS       += -mno-relax
RISCV_CFLAGS       += -nostdlib
RISCV_CFLAGS       += -nostartfiles
RISCV_CFLAGS       += -static
RISCV_CFLAGS       += -Wl,-Ttext=0
RISCV_CFLAGS       += -Wl,--build-id=none

ELF  := $(BUILDDIR)/$(APP).elf
BIN  := $(BUILDDIR)/$(APP).bin
DUMP := $(BUILDDIR)/$(APP).dump

.PHONY: all clean

all: $(BIN) $(DUMP)

clean:
	rm -rf $(BUILDDIR)

$(BUILDDIR):
	mkdir -p $@

$(ELF): $(SRC) | $(BUILDDIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BIN): $(ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(DUMP): $(ELF)
	$(RISCV_OBJDUMP) -D $< > $@
EOF
  fi

  if [[ ! -f "${src_dir}/minimal_irq.S" ]]; then
    cat > "${src_dir}/minimal_irq.S" <<'EOF'
// Minimal device payload for Occamy single-cluster simulation.
// Hart 1 raises a host software interrupt, all harts park afterwards.

.section .text
.globl _start

_start:
    csrr    a0, mhartid
    li      t0, 1
    bne     a0, t0, park

    li      t1, 0x04000000
    li      t2, 1
    sw      t2, 0(t1)
    fence   iorw, iorw

park:
    wfi
    j       park
EOF
  fi
}

ensure_roundtrip_payload() {
  local device_src_dir="${ROUNDTRIP_DEVICE_APP_DIR}/src"
  local host_src_dir="${ROUNDTRIP_HOST_APP_DIR}/src"

  mkdir -p "${device_src_dir}" "${host_src_dir}"

  if [[ ! -f "${ROUNDTRIP_DEVICE_APP_DIR}/Makefile" ]]; then
    log "creating roundtrip device app"
    cat > "${ROUNDTRIP_DEVICE_APP_DIR}/Makefile" <<'EOF'
# Copyright 2026

APP                := roundtrip
BUILDDIR           := $(abspath build)
SRC                := $(abspath src/$(APP).S)
RISCV_CC           ?= riscv64-unknown-elf-gcc
RISCV_OBJCOPY      ?= riscv64-unknown-elf-objcopy
RISCV_OBJDUMP      ?= riscv64-unknown-elf-objdump
RISCV_CFLAGS       += -march=rv32im_zicsr
RISCV_CFLAGS       += -mabi=ilp32
RISCV_CFLAGS       += -mno-relax
RISCV_CFLAGS       += -nostdlib
RISCV_CFLAGS       += -nostartfiles
RISCV_CFLAGS       += -static
RISCV_CFLAGS       += -Wl,-Ttext=0
RISCV_CFLAGS       += -Wl,--build-id=none

ELF  := $(BUILDDIR)/$(APP).elf
BIN  := $(BUILDDIR)/$(APP).bin
DUMP := $(BUILDDIR)/$(APP).dump

.PHONY: all clean

all: $(BIN) $(DUMP)

clean:
	rm -rf $(BUILDDIR)

$(BUILDDIR):
	mkdir -p $@

$(ELF): $(SRC) | $(BUILDDIR)
	$(RISCV_CC) $(RISCV_CFLAGS) $< -o $@

$(BIN): $(ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(DUMP): $(ELF)
	$(RISCV_OBJDUMP) -D $< > $@
EOF
  fi

  if [[ ! -f "${device_src_dir}/roundtrip.S" ]]; then
    cat > "${device_src_dir}/roundtrip.S" <<'EOF'
// Minimal data-path proof for Occamy single-cluster simulation.
// Hart 1 increments a 16-word host buffer whose pointer is passed
// through comm_buffer.usr_data_ptr, then signals the host.

.section .text
.globl _start

_start:
    csrr    a0, mhartid
    li      t0, 1
    bne     a0, t0, park

    // soc_ctrl_scratch_2 holds the host communication buffer pointer.
    lui     t1, 0x2000
    lw      t2, 0x1c(t1)
    lw      t3, 4(t2)

    li      t4, 16
    li      t5, 1

loop_words:
    lw      t6, 0(t3)
    add     t6, t6, t5
    sw      t6, 0(t3)
    addi    t3, t3, 4
    addi    t4, t4, -1
    bnez    t4, loop_words

    li      t1, 0x04000000
    li      t2, 1
    sw      t2, 0(t1)
    fence   iorw, iorw

park:
    wfi
    j       park
EOF
  fi

  if [[ ! -f "${ROUNDTRIP_HOST_APP_DIR}/Makefile" ]]; then
    log "creating roundtrip host app"
    cat > "${ROUNDTRIP_HOST_APP_DIR}/Makefile" <<'EOF'
# Copyright 2026

APP              = roundtrip
SRCS             = src/roundtrip.c
INCL_DEVICE_BINARY = true

include ../common.mk
EOF
  fi

  if [[ ! -f "${host_src_dir}/roundtrip.c" ]]; then
    cat > "${host_src_dir}/roundtrip.c" <<'EOF'
#include <stdint.h>

#include "host.c"

#define ROUNDTRIP_WORDS 16u

static volatile uint32_t roundtrip_buffer[ROUNDTRIP_WORDS]
    __attribute__((aligned(64)));

static int validate_roundtrip(void) {
    for (uint32_t i = 0; i < ROUNDTRIP_WORDS; ++i) {
        if (roundtrip_buffer[i] != (i + 1u)) return 1;
    }
    return 0;
}

int main(void) {
    for (uint32_t i = 0; i < ROUNDTRIP_WORDS; ++i) {
        roundtrip_buffer[i] = i;
    }

    comm_buffer.usr_data_ptr = (uint32_t)(uintptr_t)&roundtrip_buffer[0];
    fence();

    // Shared-memory state must be globally visible before the cluster starts.
    reset_and_ungate_quadrants();
    deisolate_all();
    enable_sw_interrupts();
    program_snitches();
    fence();
    wakeup_snitches_cl();
    wait_snitches_done();

    return validate_roundtrip();
}
EOF
  fi
}

main() {
  need_cmd git
  need_cmd python

  ensure_checkout
  ensure_occamy_checkout
  ensure_verilator_patch
  ensure_minimal_payload
  ensure_roundtrip_payload

  exec "${RUNNER}" "$@"
}

main "$@"
