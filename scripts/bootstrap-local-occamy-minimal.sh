#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
OCCAMY_DIR="${ROOT_DIR}/platforms/occamy"
OCCAMY_URL="https://github.com/pulp-platform/occamy.git"
OCCAMY_BRANCH="ck/fpga2"
RUNNER="${ROOT_DIR}/scripts/run-local-occamy-minimal.sh"
SIM_MAKEFILE="${OCCAMY_DIR}/target/sim/Makefile"
DEVICE_APP_DIR="${OCCAMY_DIR}/target/sim/sw/device/apps/minimal_irq"

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

main() {
  need_cmd git
  need_cmd python

  ensure_checkout
  ensure_occamy_checkout
  ensure_verilator_patch
  ensure_minimal_payload

  exec "${RUNNER}" "$@"
}

main "$@"
