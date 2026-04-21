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
SEQUENCE_SET=0
RUN_ALL=0
REPLAY_TIMEOUT="${REPLAY_TIMEOUT:-600}"
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
       scripts/run-local-occamy-openmp-replay.sh --all

Experimental M3 replay step.

It consumes the qemu-side files produced by:

  scripts/run-local-occamy-openmp-smoke.sh --capture-snapshot

Then it builds a temporary bare-metal CVA6 host harness that:

  - loads one captured fake L3 image into Verilator memory
  - relocates the captured mailbox ring-buffer state into L3 for simulator reachability
  - adapts the captured Linux-driver boot state to the sim bootrom convention
  - sends the captured four-word OpenMP launch to the real Snitch mailbox manager

This is still not a live qemu-to-Verilator bridge.

Set REPLAY_TIMEOUT to override the per-sequence Verilator timeout.  The
default is intentionally conservative because later captured launches can be
slower than the first spot-check replays.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        RUN_ALL=1
        shift
        ;;
      --sequence)
        [[ $# -ge 2 ]] || die "--sequence requires a number"
        SEQUENCE="$2"
        SEQUENCE_SET=1
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

  if [[ "${RUN_ALL}" -eq 1 && "${SEQUENCE_SET}" -eq 1 ]]; then
    die "--all cannot be combined with --sequence"
  fi
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

list_launch_sequences() {
  python3 - "${LAUNCHES_JSONL}" <<'PY'
import json
import sys
from pathlib import Path

launches_path = Path(sys.argv[1])
sequences = []
for line in launches_path.read_text().splitlines():
    if not line.strip():
        continue
    sequences.append(int(json.loads(line)["sequence"]))

for sequence in sorted(set(sequences)):
    print(sequence)
PY
}

generate_replay_sources() {
  mkdir -p "${REPLAY_DIR}"

  python3 - "${SEQUENCE}" "${LAUNCHES_JSONL}" "${SNAPSHOT_DIR}/snapshots.jsonl" \
    "${SNAPSHOT_DIR}" "${REPLAY_DIR}" <<'PY'
import json
import struct
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

l3_region = regions["l3"]
scratchpad_region = regions["scratchpad_wide"]
l3_base = int(l3_region["pbase"], 16)
scratchpad_base = int(scratchpad_region["pbase"], 16)
l3_image = (snapshot_dir / l3_region["file"]).read_bytes()
scratchpad_image = (snapshot_dir / scratchpad_region["file"]).read_bytes()

scratch = launch["soc_scratch"]
mailbox_layout = int(scratch["s2"], 16)
device_entry = int(scratch["s0"], 16)
if device_entry == 0:
    device_entry = 0xC0000000

layout_offset = mailbox_layout - l3_base
if layout_offset < 0 or layout_offset + 16 > len(l3_image):
    raise SystemExit(
        f"mailbox layout {mailbox_layout:#x} is outside L3 snapshot "
        f"{l3_base:#x}..{l3_base + len(l3_image):#x}"
    )

layout_words = struct.unpack_from("<4I", l3_image, layout_offset)
ring_addrs = layout_words[:3]
ring_struct = struct.Struct("<IIIIQQ")
spans = []

for rb_paddr in ring_addrs:
    rb_offset = rb_paddr - scratchpad_base
    if rb_offset < 0 or rb_offset + ring_struct.size > len(scratchpad_image):
        raise SystemExit(
            f"ring buffer {rb_paddr:#x} is outside scratchpad snapshot "
            f"{scratchpad_base:#x}..{scratchpad_base + len(scratchpad_image):#x}"
        )

    head, size, tail, element_size, data_v, data_p = ring_struct.unpack_from(
        scratchpad_image, rb_offset
    )
    data_bytes = size * element_size
    spans.append((rb_paddr, rb_paddr + ring_struct.size))

    if data_p != 0 and data_bytes != 0:
        data_offset = data_p - scratchpad_base
        if data_offset < 0 or data_offset + data_bytes > len(scratchpad_image):
            raise SystemExit(
                f"ring data {data_p:#x}+{data_bytes:#x} is outside scratchpad snapshot "
                f"{scratchpad_base:#x}..{scratchpad_base + len(scratchpad_image):#x}"
            )
        spans.append((data_p, data_p + data_bytes))

mailbox_snapshot_base = min(start for start, _ in spans)
mailbox_snapshot_end = max(end for _, end in spans)
mailbox_snapshot = bytearray(scratchpad_image[
    mailbox_snapshot_base - scratchpad_base : mailbox_snapshot_end - scratchpad_base
])

mailbox_snapshot_size = len(mailbox_snapshot)
search_start = max(0, len(l3_image) - 0x4000)
search_end = len(l3_image) - mailbox_snapshot_size
mailbox_replay_offset = None
for candidate in range(search_end & ~0x7, search_start - 1, -8):
    if all(byte == 0 for byte in l3_image[candidate : candidate + mailbox_snapshot_size]):
        mailbox_replay_offset = candidate
        break
if mailbox_replay_offset is None:
    raise SystemExit(
        f"could not find {mailbox_snapshot_size} zero bytes in the L3 replay heap"
    )
mailbox_replay_base = l3_base + mailbox_replay_offset

relocated_ring_addrs = []
for rb_paddr in ring_addrs:
    rel = rb_paddr - mailbox_snapshot_base
    head, size, tail, element_size, data_v, data_p = ring_struct.unpack_from(
        mailbox_snapshot, rel
    )
    relocated_rb = mailbox_replay_base + rel
    relocated_data = mailbox_replay_base + (data_p - mailbox_snapshot_base)
    ring_struct.pack_into(
        mailbox_snapshot,
        rel,
        head,
        size,
        tail,
        element_size,
        relocated_data,
        relocated_data,
    )
    relocated_ring_addrs.append(relocated_rb)

l3_replay = bytearray(l3_image)
struct.pack_into("<III", l3_replay, layout_offset, *relocated_ring_addrs)
l3_replay[
    mailbox_replay_offset : mailbox_replay_offset + mailbox_snapshot_size
] = mailbox_snapshot
(replay_dir / "l3_replay.bin").write_bytes(l3_replay)
(replay_dir / "mailbox_snapshot.bin").write_bytes(mailbox_snapshot)

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
            f"#define REPLAY_MAILBOX_ORIGINAL_BASE {c_u32(hex(mailbox_snapshot_base))}",
            f"#define REPLAY_MAILBOX_REPLAY_BASE {c_u32(hex(mailbox_replay_base))}",
            f"#define REPLAY_MAILBOX_REPLAY_SIZE {mailbox_snapshot_size}u",
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
.incbin \"{(replay_dir / 'l3_replay.bin').resolve()}\"
.balign 16
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

  log "running replay simulation (timeout ${REPLAY_TIMEOUT}s)"
  (
    cd "${SIM_DIR}"
    timeout "${REPLAY_TIMEOUT}" "${sim_bin}" "${HOST_ELF}"
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

archive_replay_artifacts() {
  local seq_dir="${REPLAY_DIR}/sequence-$(printf '%04d' "${SEQUENCE}")"
  local dev_trace="${SIM_DIR}/logs/trace_hart_00001.dasm"
  local host_trace="${SIM_DIR}/trace_hart_00.dasm"

  mkdir -p "${seq_dir}"
  cp -f "${REPLAY_DIR}/replay_config.h" "${seq_dir}/replay_config.h"
  cp -f "${HOST_DUMP}" "${seq_dir}/openmp-replay.dump"
  cp -f "${host_trace}" "${seq_dir}/trace_hart_00.dasm"
  cp -f "${dev_trace}" "${seq_dir}/trace_hart_00001.dasm"
}

run_one_sequence() {
  log "replaying captured launch ${SEQUENCE}"
  generate_replay_sources
  build_replay_host
  run_replay
  verify_replay
  archive_replay_artifacts
  log "sequence ${SEQUENCE}: success"
}

main() {
  parse_args "$@"

  need_cmd python3
  need_cmd make
  need_cmd rg
  need_cmd timeout
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

  if [[ "${RUN_ALL}" -eq 1 ]]; then
    mapfile -t sequences < <(list_launch_sequences)
    [[ "${#sequences[@]}" -gt 0 ]] || die "no launch sequences found in ${LAUNCHES_JSONL}"

    log "replaying ${#sequences[@]} captured launch sequences"
    for sequence in "${sequences[@]}"; do
      SEQUENCE="${sequence}"
      run_one_sequence
    done

    log "success"
    log "sequences: ${sequences[*]}"
    log "artifacts: ${REPLAY_DIR}/sequence-XXXX"
    exit 0
  fi

  run_one_sequence

  log "success"
  log "sequence: ${SEQUENCE}"
  log "host ELF: ${HOST_ELF}"
  log "host trace: ${SIM_DIR}/trace_hart_00.dasm"
  log "device trace: ${SIM_DIR}/logs/trace_hart_00001.dasm"
}

main "$@"
