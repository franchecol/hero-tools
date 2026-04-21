#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
SIM_DIR="${ROOT_DIR}/platforms/occamy/target/sim"
HOST_RUNTIME_DIR="${SIM_DIR}/sw/host/runtime"
HOST_SHARED_DIR="${SIM_DIR}/sw/host/../shared"
SNAPSHOT_DIR="${ROOT_DIR}/output/occamy-openmp-smoke/snapshots"
LAUNCHES_JSONL="${ROOT_DIR}/output/occamy-openmp-smoke/launches.jsonl"
REPLAY_DIR="${ROOT_DIR}/output/occamy-openmp-replay"
HOST_ELF="${REPLAY_DIR}/openmp-replay.elf"
HOST_DUMP="${REPLAY_DIR}/openmp-replay.dump"
SEQUENCE=1
CANONICAL_RISCV_PREFIX="riscv64-unknown-elf-"
RISCV_SRC_PREFIX=""
USER_BIN_DIR="${HOME}/bin"

log() {
  printf '[occamy-openmp-replay] %s\n' "$*"
}

die() {
  printf '[occamy-openmp-replay] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

usage() {
  cat <<'EOF'
Usage: scripts/run-local-occamy-openmp-replay.sh [--sequence N]

Experimental M3 replay step.

It consumes the qemu-side files produced by:

  scripts/run-local-occamy-openmp-smoke.sh --capture-snapshot

Then it builds a temporary bare-metal CVA6 host harness that:

  - loads one captured fake L3 image into Verilator memory
  - loads one captured fake scratchpad-wide image into Verilator memory
  - adapts the captured Linux-driver boot state to the sim bootrom convention
  - sends the captured four-word OpenMP launch to the real Snitch mailbox manager

This is still not a live qemu-to-Verilator bridge.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sequence)
        [[ $# -ge 2 ]] || die "--sequence requires a number"
        SEQUENCE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

normalize_tool_prefix() {
  local prefix="$1"
  [[ -n "${prefix}" && "${prefix}" != *- ]] && prefix="${prefix}-"
  printf '%s\n' "${prefix}"
}

find_riscv_tool_prefix() {
  local prefix
  local requested_prefix="${RISCV_TOOL_PREFIX:-}"
  local prefixes=()

  if [[ -n "${requested_prefix}" ]]; then
    prefix=$(normalize_tool_prefix "${requested_prefix}")
    command -v "${prefix}gcc" >/dev/null 2>&1 || \
      die "requested RISCV_TOOL_PREFIX does not provide ${prefix}gcc"
    printf '%s\n' "${prefix}"
    return 0
  fi

  prefixes=(
    "${CANONICAL_RISCV_PREFIX}"
    "riscv64-elf-"
    "riscv64-none-elf-"
  )

  for prefix in "${prefixes[@]}"; do
    if command -v "${prefix}gcc" >/dev/null 2>&1 && \
       command -v "${prefix}objdump" >/dev/null 2>&1; then
      printf '%s\n' "${prefix}"
      return 0
    fi
  done

  return 1
}

ensure_riscv_aliases() {
  local tool
  local src

  RISCV_SRC_PREFIX=$(find_riscv_tool_prefix) || \
    die "could not find a supported bare-metal RISC-V tool prefix"

  mkdir -p "${USER_BIN_DIR}"
  export PATH="${USER_BIN_DIR}:${PATH}"

  if [[ "${RISCV_SRC_PREFIX}" != "${CANONICAL_RISCV_PREFIX}" ]]; then
    log "mapping RISC-V tool prefix ${RISCV_SRC_PREFIX} to ${CANONICAL_RISCV_PREFIX} via ${USER_BIN_DIR}"
  fi

  for tool in gcc objdump; do
    if [[ "${RISCV_SRC_PREFIX}" == "${CANONICAL_RISCV_PREFIX}" ]]; then
      continue
    fi
    src=$(command -v "${RISCV_SRC_PREFIX}${tool}" || true)
    [[ -n "${src}" ]] && ln -sf "${src}" "${USER_BIN_DIR}/${CANONICAL_RISCV_PREFIX}${tool}"
  done

  need_cmd "${CANONICAL_RISCV_PREFIX}gcc"
  need_cmd "${CANONICAL_RISCV_PREFIX}objdump"
}

resolve_verilator_root() {
  local candidate=""
  local verilator_bin=""
  local resolved_bin=""

  if [[ -n "${VERILATOR_ROOT:-}" ]]; then
    candidate="${VERILATOR_ROOT}"
  else
    candidate=$(verilator -V 2>/dev/null | awk -F'= ' '
      /VERILATOR_ROOT/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        if ($2 != "") {
          root = $2
        }
      }
      END {
        print root
      }
    ')
  fi

  if [[ -z "${candidate}" ]]; then
    verilator_bin=$(command -v verilator)
    resolved_bin=$(readlink -f "${verilator_bin}" 2>/dev/null || printf '%s\n' "${verilator_bin}")
    for candidate in \
      "$(dirname -- "${resolved_bin}")/../share/verilator" \
      "$(dirname -- "${resolved_bin}")/../lib/verilator" \
      "/usr/share/verilator" \
      "/usr/local/share/verilator"; do
      if [[ -f "${candidate}/include/verilated.cpp" ]]; then
        break
      fi
    done
  fi

  [[ -n "${candidate}" ]] || die "could not determine VERILATOR_ROOT"
  [[ -f "${candidate}/include/verilated.cpp" ]] || \
    die "invalid VERILATOR_ROOT: ${candidate}"

  export VERILATOR_ROOT
  VERILATOR_ROOT=$(cd -- "${candidate}" && pwd)
  export VLT_ROOT="${VERILATOR_ROOT}"

  log "using VERILATOR_ROOT=${VERILATOR_ROOT}"
}

build_simulator() {
  log "building reduced Occamy headers"
  make -C "${SIM_DIR}" CFG_OVERRIDE=cfg/single-cluster.hjson VERIBLE_FMT=true all-headers

  log "building Verilator simulator"
  make -C "${SIM_DIR}" CFG_OVERRIDE=cfg/single-cluster.hjson VERIBLE_FMT=true \
    VLT='verilator --timing -DASSERTS_OFF' \
    VERILATOR_ROOT="${VERILATOR_ROOT}" \
    VLT_ROOT="${VLT_ROOT}" \
    CXXFLAGS='-include cstdint -fcoroutines' \
    bin/occamy_top.vlt
}

ensure_snapshots() {
  if [[ ! -s "${LAUNCHES_JSONL}" || ! -s "${SNAPSHOT_DIR}/snapshots.jsonl" ]]; then
    log "missing capture snapshot; generating it now"
    "${ROOT_DIR}/scripts/run-local-occamy-openmp-smoke.sh" --capture-snapshot
  fi
}

generate_replay_sources() {
  mkdir -p "${REPLAY_DIR}"

  python3 - "${SEQUENCE}" "${LAUNCHES_JSONL}" "${SNAPSHOT_DIR}/snapshots.jsonl" \
    "${SNAPSHOT_DIR}" "${REPLAY_DIR}" <<'PY'
import json
import sys
from pathlib import Path

sequence = int(sys.argv[1], 0)
launches_path = Path(sys.argv[2])
snapshots_path = Path(sys.argv[3])
snapshot_dir = Path(sys.argv[4])
replay_dir = Path(sys.argv[5])

launch = None
for line in launches_path.read_text().splitlines():
    if not line.strip():
        continue
    record = json.loads(line)
    if record["sequence"] == sequence:
        launch = record
        break
if launch is None:
    raise SystemExit(f"missing launch sequence {sequence} in {launches_path}")

snapshot = None
for line in snapshots_path.read_text().splitlines():
    if not line.strip():
        continue
    record = json.loads(line)
    if record["sequence"] == sequence:
        snapshot = record
        break
if snapshot is None:
    raise SystemExit(f"missing snapshot sequence {sequence} in {snapshots_path}")

regions = {region["name"]: region for region in snapshot["regions"]}
for required in ("l3", "scratchpad_wide"):
    if required not in regions:
        raise SystemExit(f"snapshot {sequence} has no {required} region")

def c_u32(value):
    return f"0x{int(value, 16):08x}u"

scratch = launch["soc_scratch"]
mailbox_layout = int(scratch["s2"], 16)
device_entry = int(scratch["s0"], 16)
if device_entry == 0:
    device_entry = 0xC0000000

config = replay_dir / "replay_config.h"
config.write_text(
    "\n".join(
        [
            "#pragma once",
            f"#define REPLAY_SEQUENCE {sequence}u",
            f"#define REPLAY_DEVICE_ENTRY {c_u32(hex(device_entry))}",
            f"#define REPLAY_MAILBOX_LAYOUT {c_u32(hex(mailbox_layout))}",
            f"#define REPLAY_TARGET_FN {c_u32(launch['target_fn'])}",
            f"#define REPLAY_ARG_PTR {c_u32(launch['arg_ptr'])}",
            f"#define REPLAY_WORKERS {int(launch['workers'])}u",
            "",
        ]
    ),
    encoding="utf-8",
)

snapshot_asm = replay_dir / "snapshot.S"
snapshot_asm.write_text(
    f"""
.section .replay_l3,\"aw\",@progbits
.balign 16
.incbin \"{(snapshot_dir / regions['l3']['file']).resolve()}\"
.balign 16
.section .rodata.snapshot_scratchpad_wide,\"a\",@progbits
.balign 16
.global snapshot_scratchpad_wide_start
.global snapshot_scratchpad_wide_end
snapshot_scratchpad_wide_start:
.incbin \"{(snapshot_dir / regions['scratchpad_wide']['file']).resolve()}\"
snapshot_scratchpad_wide_end:
""".lstrip(),
    encoding="utf-8",
)
PY

  cat > "${REPLAY_DIR}/replay_host.ld" <<'EOF'
ENTRY(_start)

MEMORY
{
    DRAM (rwxa) : ORIGIN = 0x80000000, LENGTH = 0x80000000
}

SECTIONS
{
  .appl :
  {
    __stack_pointer$  = . + 0x70000;
    *(.text.startup)
    *(.text .text.*)
    __SDATA_BEGIN__ = .;
    __global_pointer$ = . + 0x7f0;
    *(.sdata)
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata .srodata.*)
    *(.sdata .sdata.* .gnu.linkonce.s.*)
    *(.data)
    *(.rodata .rodata.*)
  } > DRAM

  .htif : { *(.htif) } > DRAM

  .bss (NOLOAD) :
  {
    . = ALIGN(8);
    __bss_start = . ;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(8);
    __bss_end = . ;
  } > DRAM

  .wide_spm :
  {
    . = ALIGN(8);
    __wide_spm_start = . ;
    *(.wide_spm)
    . = ALIGN(8);
    __wide_spm_end = . ;
  } > DRAM

  __end = .;

  .replay_l3 0xC0000000 :
  {
    KEEP(*(.replay_l3))
  } > DRAM

  .devicebin : { *(.devicebin) } > DRAM

  /DISCARD/ : { *(.riscv.attributes) *(.comment) }
}
EOF

  cat > "${REPLAY_DIR}/replay.c" <<'EOF'
#include <stddef.h>
#include <stdint.h>

#include "replay_config.h"
#include "host.c"

#define SCRATCHPAD_WIDE_BASE 0x71000000u

#define MBOX_DEVICE_START 0x02u
#define MBOX_DEVICE_DONE 0x04u

struct ring_buf {
    uint32_t head;
    uint32_t size;
    uint32_t tail;
    uint32_t element_size;
    uint64_t data_v;
    uint64_t data_p;
};

extern const uint8_t snapshot_scratchpad_wide_start[];
extern const uint8_t snapshot_scratchpad_wide_end[];

static const uint8_t *scratchpad_snapshot_ptr(uintptr_t paddr) {
    return snapshot_scratchpad_wide_start + (paddr - SCRATCHPAD_WIDE_BASE);
}

static void copy_to_device(uintptr_t dst_addr, const uint8_t *src, size_t bytes) {
    volatile uint64_t *dst64 = (volatile uint64_t *)dst_addr;
    const uint64_t *src64 = (const uint64_t *)src;
    size_t words = bytes / sizeof(uint64_t);

    for (size_t i = 0; i < words; ++i) {
        dst64[i] = src64[i];
    }

    for (size_t i = words * sizeof(uint64_t); i < bytes; ++i) {
        ((volatile uint8_t *)dst_addr)[i] = src[i];
    }
}

static void copy_ring_snapshot(uintptr_t rb_paddr) {
    const struct ring_buf *src_rb = (const struct ring_buf *)scratchpad_snapshot_ptr(rb_paddr);
    size_t data_bytes = (size_t)src_rb->size * (size_t)src_rb->element_size;

    copy_to_device(rb_paddr, (const uint8_t *)src_rb, sizeof(*src_rb));
    if (src_rb->data_p != 0 && data_bytes != 0) {
        copy_to_device((uintptr_t)src_rb->data_p,
                       scratchpad_snapshot_ptr((uintptr_t)src_rb->data_p),
                       data_bytes);
    }
}

static void copy_scratchpad_snapshot(void) {
    volatile uint32_t *layout = (volatile uint32_t *)(uintptr_t)REPLAY_MAILBOX_LAYOUT;

    copy_ring_snapshot(layout[0]);
    copy_ring_snapshot(layout[1]);
    copy_ring_snapshot(layout[2]);
    fence();
}

static volatile struct ring_buf *layout_word(unsigned index) {
    volatile uint32_t *layout = (volatile uint32_t *)(uintptr_t)REPLAY_MAILBOX_LAYOUT;
    return (volatile struct ring_buf *)(uintptr_t)layout[index];
}

static int rb_host_put_word(volatile struct ring_buf *rb, uint32_t word) {
    uint32_t next_head = (rb->head + 1u) % rb->size;
    if (next_head == rb->tail) return -1;
    ((volatile uint32_t *)(uintptr_t)rb->data_v)[rb->head] = word;
    rb->head = next_head;
    fence();
    return 0;
}

static int rb_host_get_word(volatile struct ring_buf *rb, uint32_t *word) {
    if (rb->tail == rb->head) return -1;
    *word = ((volatile uint32_t *)(uintptr_t)rb->data_v)[rb->tail];
    rb->tail = (rb->tail + 1u) % rb->size;
    fence();
    return 0;
}

static void mbox_write(uint32_t word) {
    volatile struct ring_buf *h2a_mbox = layout_word(2);
    while (rb_host_put_word(h2a_mbox, word)) {
        fence();
    }
}

static int mbox_read_bounded(uint32_t *word) {
    volatile struct ring_buf *a2h_mbox = layout_word(1);
    for (volatile uint64_t i = 0; i < 100000000ull; ++i) {
        if (rb_host_get_word(a2h_mbox, word) == 0) {
            return 0;
        }
        fence();
    }
    return -1;
}

int main(void) {
    uint32_t done = 0;
    uint32_t cycles = 0;
    uint32_t dma_wait_cycles = 0;

    set_d_cache_enable(0);
    copy_scratchpad_snapshot();

    reset_and_ungate_quadrants();
    deisolate_all();

    *soc_ctrl_scratch_ptr(1) = REPLAY_DEVICE_ENTRY;
    *soc_ctrl_scratch_ptr(2) = REPLAY_MAILBOX_LAYOUT;

    fence();
    wakeup_snitches_cl();

    mbox_write(MBOX_DEVICE_START);
    mbox_write(REPLAY_TARGET_FN);
    mbox_write(REPLAY_ARG_PTR);
    mbox_write(REPLAY_WORKERS);

    if (mbox_read_bounded(&done)) return 2;
    if (mbox_read_bounded(&cycles)) return 3;
    if (mbox_read_bounded(&dma_wait_cycles)) return 4;
    (void)cycles;
    (void)dma_wait_cycles;

    return done == MBOX_DEVICE_DONE ? 0 : 5;
}
EOF
}

build_replay_host() {
  log "building replay host for captured launch ${SEQUENCE}"
  "${CANONICAL_RISCV_PREFIX}gcc" \
    -I"${REPLAY_DIR}" \
    -I"${HOST_RUNTIME_DIR}" \
    -I"${HOST_SHARED_DIR}/platform/generated" \
    -I"${HOST_SHARED_DIR}/platform" \
    -I"${HOST_SHARED_DIR}/runtime" \
    -march=rv64imafdc \
    -mabi=lp64d \
    -mcmodel=medany \
    -ffast-math \
    -fno-builtin-printf \
    -fno-common \
    -O3 \
    -ffunction-sections \
    -Wextra \
    -Werror \
    -nostartfiles \
    -lm \
    -lgcc \
    -T"${REPLAY_DIR}/replay_host.ld" \
    "${REPLAY_DIR}/replay.c" \
    "${REPLAY_DIR}/snapshot.S" \
    "${HOST_RUNTIME_DIR}/start.S" \
    -o "${HOST_ELF}"

  "${CANONICAL_RISCV_PREFIX}objdump" -D "${HOST_ELF}" > "${HOST_DUMP}"
}

run_replay() {
  local sim_bin="${SIM_DIR}/bin/occamy_top.vlt"

  [[ -x "${sim_bin}" ]] || die "simulator missing: ${sim_bin}"
  [[ -f "${HOST_ELF}" ]] || die "host ELF missing: ${HOST_ELF}"

  rm -f "${SIM_DIR}/uart0.log" "${SIM_DIR}/trace_hart_00.dasm"
  rm -f "${SIM_DIR}/logs/trace_hart_0000"*.dasm

  log "running replay simulation"
  (
    cd "${SIM_DIR}"
    "${sim_bin}" "${HOST_ELF}"
  )
}

verify_replay() {
  local host_trace="${SIM_DIR}/trace_hart_00.dasm"
  local dev_trace="${SIM_DIR}/logs/trace_hart_00001.dasm"
  local target_fn=""

  [[ -f "${host_trace}" ]] || die "missing host trace: ${host_trace}"
  [[ -f "${dev_trace}" ]] || die "missing device trace: ${dev_trace}"

  target_fn=$(awk '/REPLAY_TARGET_FN/ { print $3 }' "${REPLAY_DIR}/replay_config.h" | tr -d 'u')
  [[ -n "${target_fn}" ]] || die "could not read REPLAY_TARGET_FN"

  rg -q "${target_fn}" "${dev_trace}" || \
    die "device trace does not show execution at captured target ${target_fn}"
  rg -q '0x80000068.*00a2a023' "${host_trace}" || \
    die "host trace does not show the tohost exit write"
}

main() {
  parse_args "$@"

  need_cmd python3
  need_cmd make
  need_cmd rg
  need_cmd bender
  need_cmd verilator
  need_cmd dtc
  need_cmd bc
  need_cmd gcc
  need_cmd g++
  need_cmd c++
  need_cmd ar
  need_cmd ld

  ensure_riscv_aliases
  resolve_verilator_root
  build_simulator
  ensure_snapshots
  generate_replay_sources
  build_replay_host
  run_replay
  verify_replay

  log "success"
  log "sequence: ${SEQUENCE}"
  log "host ELF: ${HOST_ELF}"
  log "host trace: ${SIM_DIR}/trace_hart_00.dasm"
  log "device trace: ${SIM_DIR}/logs/trace_hart_00001.dasm"
}

main "$@"
