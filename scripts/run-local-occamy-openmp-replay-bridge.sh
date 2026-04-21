#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BRIDGE_DIR="${ROOT_DIR}/output/occamy-openmp-bridge"
REQUEST_DIR="${BRIDGE_DIR}/requests"
RESPONSE_DIR="${BRIDGE_DIR}/responses"
BRIDGE_LOG="${BRIDGE_DIR}/bridge.log"
SMOKE_LOG="${BRIDGE_DIR}/smoke-wrapper.log"
LAUNCHES_JSONL="${ROOT_DIR}/output/occamy-openmp-smoke/launches.jsonl"
REPLAY_DIR="${ROOT_DIR}/output/occamy-openmp-replay"
MAX_LAUNCHES=1
REPLAY_TIMEOUT="${REPLAY_TIMEOUT:-600}"
BRIDGE_TIMEOUT="${OCCAMY_FAKE_BRIDGE_TIMEOUT_SECONDS:-900}"
USER_TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-}"
SMOKE_TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1200}"
SMOKE_PID=""

log() {
  printf '[occamy-openmp-bridge] %s\n' "$*"
}

die() {
  printf '[occamy-openmp-bridge] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/run-local-occamy-openmp-replay-bridge.sh [--max-launches N]
       scripts/run-local-occamy-openmp-replay-bridge.sh --all

Experimental live M3 replay bridge.

The qemu/Linux HeroSDK OpenMP host still uses the fake Occamy Linux driver ABI,
but each bridged launch is no longer completed immediately.  Instead:

  - the fake driver captures the launch and memory snapshot
  - the fake driver publishes a request and blocks
  - this native wrapper runs the Verilator replay for that launch
  - the wrapper may publish qemu-visible W32 data updates from the replay trace
  - the fake driver returns MBOX_DEVICE_DONE only if replay succeeds and then
    applies any W32 updates in the response

By default only the first launch is bridged to keep the smoke bounded.  Use
--all to bridge every captured launch.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        MAX_LAUNCHES=0
        shift
        ;;
      --max-launches)
        [[ $# -ge 2 ]] || die "--max-launches requires a number"
        MAX_LAUNCHES="$2"
        [[ "${MAX_LAUNCHES}" =~ ^[0-9]+$ ]] || die "--max-launches must be numeric"
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

configure_timeouts() {
  if [[ -n "${USER_TIMEOUT_SECONDS}" ]]; then
    return
  fi

  if [[ ! "${REPLAY_TIMEOUT}" =~ ^[0-9]+$ ]]; then
    SMOKE_TIMEOUT_SECONDS=1200
    return
  fi

  if [[ "${MAX_LAUNCHES}" -eq 0 ]]; then
    SMOKE_TIMEOUT_SECONDS=7200
  else
    SMOKE_TIMEOUT_SECONDS=$((MAX_LAUNCHES * (REPLAY_TIMEOUT + 120) + 300))
  fi
}

cleanup() {
  if [[ -n "${SMOKE_PID}" ]] && kill -0 "${SMOKE_PID}" 2>/dev/null; then
    kill "${SMOKE_PID}" 2>/dev/null || true
  fi
}

prepare_bridge_dir() {
  rm -rf "${BRIDGE_DIR}"
  mkdir -p "${REQUEST_DIR}" "${RESPONSE_DIR}"
  : > "${BRIDGE_LOG}"
}

start_smoke() {
  log "starting qemu OpenMP host with replay bridge"
  log "bridge max launches: ${MAX_LAUNCHES} (0 means all)"
  log "qemu timeout: ${SMOKE_TIMEOUT_SECONDS}s"
  log "bridge dir: ${BRIDGE_DIR}"

  (
    cd "${ROOT_DIR}"
    TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS}" \
    REPLAY_TIMEOUT="${REPLAY_TIMEOUT}" \
    OCCAMY_FAKE_BRIDGE_DIR="${BRIDGE_DIR}" \
    OCCAMY_FAKE_BRIDGE_MAX_LAUNCHES="${MAX_LAUNCHES}" \
    OCCAMY_FAKE_BRIDGE_TIMEOUT_SECONDS="${BRIDGE_TIMEOUT}" \
      "${ROOT_DIR}/scripts/run-local-occamy-openmp-smoke.sh" --capture-snapshot
  ) >"${SMOKE_LOG}" 2>&1 &
  SMOKE_PID=$!
}

request_sequence() {
  local request_file="$1"
  local base
  local seq_text

  base=$(basename -- "${request_file}")
  seq_text="${base#request-}"
  seq_text="${seq_text%.json}"
  printf '%d\n' "$((10#${seq_text}))"
}

derive_copyback_updates() {
  local sequence="$1"
  local seq_text="$2"
  local trace_path="${REPLAY_DIR}/sequence-${seq_text}/trace_hart_00001.dasm"

  [[ -f "${trace_path}" ]] || return 0

  python3 - "${sequence}" "${LAUNCHES_JSONL}" "${trace_path}" <<'PY'
import json
import re
import sys
from pathlib import Path

sequence = int(sys.argv[1], 0)
launches_path = Path(sys.argv[2])
trace_path = Path(sys.argv[3])

launch = None
for line in launches_path.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    record = json.loads(line)
    if int(record["sequence"]) == sequence:
        launch = record
        break

if launch is None:
    raise SystemExit(f"missing launch sequence {sequence} in {launches_path}")

arg_ptrs = set()
for word in launch.get("arg_words", []):
    if not isinstance(word, str):
        continue
    try:
        value = int(word, 16)
    except ValueError:
        continue
    if value >= 0xC0000000:
        arg_ptrs.add(value)

if not arg_ptrs:
    raise SystemExit(0)

field_re = re.compile(r"'([^']+)': 0x([0-9a-fA-F]+)")
writes = {}

for line in trace_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if "'is_store': 0x1" not in line:
        continue
    fields = {name: int(value, 16) for name, value in field_re.findall(line)}
    addr = fields.get("opa")
    if addr not in arg_ptrs:
        continue

    candidates = []
    for key in ("gpr_rdata_1", "ld_result_32"):
        if key in fields:
            candidates.append(fields[key])

    selected = None
    for value in candidates:
        if value <= 0xFFFFFFFF and value not in arg_ptrs:
            selected = value
            break
    if selected is None:
        for value in candidates:
            if value <= 0xFFFFFFFF:
                selected = value
                break
    if selected is None:
        continue

    writes[addr] = selected

for addr in sorted(writes):
    print(f"W32 0x{addr:08x} 0x{writes[addr] & 0xFFFFFFFF:08x}")
PY
}

publish_response() {
  local seq_text="$1"
  local status="$2"
  local sequence="$3"
  local response_tmp="${RESPONSE_DIR}/response-${seq_text}.tmp"
  local updates_tmp="${response_tmp}.updates"
  local response_path="${RESPONSE_DIR}/response-${seq_text}.status"

  : > "${updates_tmp}"
  if [[ "${status}" -eq 0 ]]; then
    if ! derive_copyback_updates "${sequence}" "${seq_text}" > "${updates_tmp}"; then
      status=1
      : > "${updates_tmp}"
      printf '[occamy-openmp-bridge] failed to derive copyback updates for launch %s\n' \
        "${sequence}" >> "${BRIDGE_LOG}"
    fi
  fi

  printf '%s\n' "${status}" > "${response_tmp}"
  cat "${updates_tmp}" >> "${response_tmp}"
  rm -f "${updates_tmp}"
  mv -f "${response_tmp}" "${response_path}"
  return "${status}"
}

handle_request() {
  local request_file="$1"
  local base
  local seq_text
  local sequence
  local seq_dir
  local response_path
  local status=0

  base=$(basename -- "${request_file}")
  seq_text="${base#request-}"
  seq_text="${seq_text%.json}"
  response_path="${RESPONSE_DIR}/response-${seq_text}.status"
  [[ -e "${response_path}" ]] && return 0

  sequence=$(request_sequence "${request_file}")
  seq_dir="${BRIDGE_DIR}/sequence-${seq_text}"
  mkdir -p "${seq_dir}"

  log "replaying bridged launch ${sequence}"
  {
    printf '[occamy-openmp-bridge] request %s\n' "${request_file}"
    cat "${request_file}"
    printf '\n'
  } >> "${BRIDGE_LOG}"

  set +e
  REPLAY_TIMEOUT="${REPLAY_TIMEOUT}" \
    "${ROOT_DIR}/scripts/run-local-occamy-openmp-replay.sh" --sequence "${sequence}" \
    >"${seq_dir}/replay.log" 2>&1
  status=$?
  set -e

  if ! publish_response "${seq_text}" "${status}" "${sequence}"; then
    status=1
  fi
  if [[ "${status}" -eq 0 ]]; then
    local update_count
    update_count=$(grep -c '^W32 ' "${response_path}" || true)
    if [[ "${update_count}" -gt 0 ]]; then
      log "bridged launch ${sequence}: success (${update_count} copyback writes)"
    else
      log "bridged launch ${sequence}: success"
    fi
  else
    log "bridged launch ${sequence}: failed with status ${status}"
  fi

  return 0
}

service_requests_once() {
  local request_file

  for request_file in "${REQUEST_DIR}"/request-*.json; do
    [[ -e "${request_file}" ]] || continue
    handle_request "${request_file}"
  done
}

wait_for_smoke() {
  local status=0

  while kill -0 "${SMOKE_PID}" 2>/dev/null; do
    service_requests_once
    sleep 1
  done
  service_requests_once

  set +e
  wait "${SMOKE_PID}"
  status=$?
  set -e
  SMOKE_PID=""

  if [[ "${status}" -ne 0 ]]; then
    tail -n 60 "${SMOKE_LOG}" >&2 || true
    die "qemu OpenMP host failed with status ${status}; see ${SMOKE_LOG}"
  fi
}

verify_bridge() {
  local responses

  responses=$(find "${RESPONSE_DIR}" -maxdepth 1 -type f -name 'response-*.status' | wc -l)
  if [[ "${responses}" -eq 0 ]]; then
    die "no replay bridge requests were serviced"
  fi
  if [[ "${MAX_LAUNCHES}" -ne 0 && "${responses}" -ne "${MAX_LAUNCHES}" ]]; then
    die "expected ${MAX_LAUNCHES} replay bridge responses, saw ${responses}"
  fi
  while IFS= read -r response_path; do
    local first_line
    first_line=$(head -n 1 "${response_path}")
    [[ "${first_line}" == "0" ]] || \
      die "one or more replay bridge responses failed; see ${BRIDGE_DIR}"
  done < <(find "${RESPONSE_DIR}" -maxdepth 1 -type f -name 'response-*.status' | sort)
}

main() {
  parse_args "$@"
  configure_timeouts
  trap cleanup EXIT

  command -v rg >/dev/null 2>&1 || die "missing command: rg"
  command -v timeout >/dev/null 2>&1 || die "missing command: timeout"

  prepare_bridge_dir
  start_smoke
  wait_for_smoke
  verify_bridge

  log "success"
  log "bridged responses: ${RESPONSE_DIR}"
  log "qemu smoke log: ${SMOKE_LOG}"
}

main "$@"
