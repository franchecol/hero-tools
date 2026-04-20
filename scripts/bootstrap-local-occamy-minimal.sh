#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
OCCAMY_DIR="${ROOT_DIR}/platforms/occamy"
OCCAMY_URL="${OCCAMY_URL:-https://github.com/franchecol/occamy.git}"
OCCAMY_BRANCH="${OCCAMY_BRANCH:-occamy-minimal-bootstrap}"
RUNNER="${ROOT_DIR}/scripts/run-local-occamy-minimal.sh"
SIM_MAKEFILE="${OCCAMY_DIR}/target/sim/Makefile"

REQUIRED_OCCAMY_FILES=(
  "${OCCAMY_DIR}/target/sim/sw/device/apps/minimal_irq/Makefile"
  "${OCCAMY_DIR}/target/sim/sw/device/apps/minimal_irq/src/minimal_irq.S"
  "${OCCAMY_DIR}/target/sim/sw/device/apps/roundtrip/Makefile"
  "${OCCAMY_DIR}/target/sim/sw/device/apps/roundtrip/src/roundtrip.S"
  "${OCCAMY_DIR}/target/sim/sw/host/apps/roundtrip/Makefile"
  "${OCCAMY_DIR}/target/sim/sw/host/apps/roundtrip/src/roundtrip.c"
)

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

normalize_remote() {
  local remote="${1}"

  case "${remote}" in
    https://github.com/*)
      printf '%s\n' "${remote#https://github.com/}"
      ;;
    http://github.com/*)
      printf '%s\n' "${remote#http://github.com/}"
      ;;
    git@github.com:*)
      printf '%s\n' "${remote#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      printf '%s\n' "${remote#ssh://git@github.com/}"
      ;;
    *)
      printf '%s\n' "${remote}"
      ;;
  esac
}

same_remote_target() {
  [[ "$(normalize_remote "$1")" == "$(normalize_remote "$2")" ]]
}

ensure_checkout() {
  [[ -d "${ROOT_DIR}/.git" ]] || \
    die "bootstrap must run from a hero-tools checkout"
  [[ -x "${RUNNER}" ]] || \
    die "missing runner script: ${RUNNER}"
}

ensure_occamy_checkout() {
  local origin
  local fork
  local branch

  mkdir -p "${ROOT_DIR}/platforms"

  if [[ ! -d "${OCCAMY_DIR}/.git" ]]; then
    log "cloning Occamy (${OCCAMY_BRANCH}) into ${OCCAMY_DIR}"
    git clone --branch "${OCCAMY_BRANCH}" --single-branch "${OCCAMY_URL}" "${OCCAMY_DIR}"
    return
  fi

  origin=$(git -C "${OCCAMY_DIR}" remote get-url origin 2>/dev/null || true)
  fork=$(git -C "${OCCAMY_DIR}" remote get-url fork 2>/dev/null || true)
  if [[ -z "${origin}" && -z "${fork}" ]]; then
    die "existing ${OCCAMY_DIR} checkout has neither origin nor fork remote"
  fi
  if ! same_remote_target "${origin}" "${OCCAMY_URL}" && \
     ! same_remote_target "${fork}" "${OCCAMY_URL}"; then
    die "existing ${OCCAMY_DIR} checkout does not point to expected Occamy fork ${OCCAMY_URL}"
  fi

  branch=$(git -C "${OCCAMY_DIR}" branch --show-current || true)
  [[ "${branch}" == "${OCCAMY_BRANCH}" ]] || \
    die "existing ${OCCAMY_DIR} checkout is on '${branch:-detached}', expected '${OCCAMY_BRANCH}'"
}

require_occamy_branch_content() {
  [[ -f "${SIM_MAKEFILE}" ]] || die "missing simulator Makefile: ${SIM_MAKEFILE}"

  grep -q 'verilated_timing.o' "${SIM_MAKEFILE}" || \
    die "expected Verilator compatibility fix in ${SIM_MAKEFILE}; clone the expected Occamy fork branch"
  grep -q 'verilated_threads.o' "${SIM_MAKEFILE}" || \
    die "expected Verilator compatibility fix in ${SIM_MAKEFILE}; clone the expected Occamy fork branch"

  local required_file

  for required_file in "${REQUIRED_OCCAMY_FILES[@]}"; do
    [[ -f "${required_file}" ]] || \
      die "missing required Occamy branch file: ${required_file}"
  done
}

main() {
  need_cmd git
  need_cmd python

  ensure_checkout
  ensure_occamy_checkout
  require_occamy_branch_content

  exec "${RUNNER}" "$@"
}

main "$@"
