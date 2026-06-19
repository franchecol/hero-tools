#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
M3_LOCK_FILE="${SCRIPT_DIR}/occamy-m3.lock.env"

if [[ "$#" -ne 0 ]]; then
  printf '[occamy-m3-bootstrap] ERROR: M3 takes no mode argument; use environment variables for build options\n' >&2
  exit 1
fi

[[ -f "${M3_LOCK_FILE}" ]] || {
  printf '[occamy-m3-bootstrap] ERROR: missing lock file: %s\n' "${M3_LOCK_FILE}" >&2
  exit 1
}
# shellcheck disable=SC1090
source "${M3_LOCK_FILE}"

git -C "${ROOT_DIR}" submodule update --init toolchain/llvm-project

llvm_head=$(git -C "${ROOT_DIR}/toolchain/llvm-project" rev-parse HEAD)
[[ "${llvm_head}" == "${OCCAMY_M3_LLVM_COMMIT}" ]] || {
  printf '[occamy-m3-bootstrap] ERROR: LLVM HEAD is %s, expected %s\n' \
    "${llvm_head}" "${OCCAMY_M3_LLVM_COMMIT}" >&2
  exit 1
}

if [[ ! -x "${ROOT_DIR}/install/bin/riscv32-unknown-elf-clang" || \
      ! -d "${ROOT_DIR}/install/rv32imafd-ilp32d/riscv32-unknown-elf" ]]; then
  printf '[occamy-m3-bootstrap] building pinned RV32 LLVM toolchain and sysroot\n'
  (
    cd "${ROOT_DIR}"
    # shellcheck disable=SC1091
    source scripts/setenv.sh
    make hero-tc-llvm-axpy
  )
fi

exec "${SCRIPT_DIR}/bootstrap-local-occamy-minimal.sh" omp_mailbox
