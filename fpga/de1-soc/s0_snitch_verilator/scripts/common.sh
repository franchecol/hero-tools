#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S0_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(git -C "${S0_DIR}" rev-parse --show-toplevel)
OCCAMY_DIR="${REPO_ROOT}/platforms/occamy"

if [[ -n "${SNITCH_CLUSTER_ROOT:-}" ]]; then
    SNITCH_ROOT="${SNITCH_CLUSTER_ROOT}"
else
    SNITCH_ROOT=$(
        find "${OCCAMY_DIR}/.bender/git/checkouts" \
            -maxdepth 1 \
            -type d \
            -name 'snitch_cluster-*' \
            | sort \
            | tail -n 1
    )
fi

if [[ -z "${SNITCH_ROOT}" || ! -d "${SNITCH_ROOT}/target/snitch_cluster" ]]; then
    echo "Could not find Snitch cluster checkout under ${OCCAMY_DIR}/.bender/git/checkouts" >&2
    exit 1
fi

SNITCH_TARGET="${SNITCH_ROOT}/target/snitch_cluster"
SNITCH_CFG="${S0_DIR}/cfg/one-core.hjson"
SNITCH_LLVM_BIN="${SNITCH_LLVM_BIN:-${REPO_ROOT}/install/bin}"
OCCAMY_PYTHON_VENV="${OCCAMY_PYTHON_VENV:-${REPO_ROOT}/.venv-occamy}"
SNITCH_NEWLIB="${SNITCH_NEWLIB:-${REPO_ROOT}/install/rv32imafd-ilp32d/riscv32-unknown-elf}"
SNITCH_LLVM_VER="$("${SNITCH_LLVM_BIN}/llvm-config" --version)"
SNITCH_LLVM_VER_DIR="${SNITCH_LLVM_VER%git}"
if [[ -z "${SNITCH_COMPILER_RT:-}" ]]; then
    if [[ -f "${REPO_ROOT}/install/lib/clang/${SNITCH_LLVM_VER}/rv32imafd-ilp32d/lib/libclang_rt.builtins-riscv32.a" ]]; then
        SNITCH_COMPILER_RT="${REPO_ROOT}/install/lib/clang/${SNITCH_LLVM_VER}/rv32imafd-ilp32d/lib"
    elif [[ -f "${REPO_ROOT}/install/lib/clang/${SNITCH_LLVM_VER_DIR}/rv32imafd-ilp32d/lib/libclang_rt.builtins-riscv32.a" ]]; then
        SNITCH_COMPILER_RT="${REPO_ROOT}/install/lib/clang/${SNITCH_LLVM_VER_DIR}/rv32imafd-ilp32d/lib"
    else
        echo "Could not find Snitch compiler-rt builtins for LLVM ${SNITCH_LLVM_VER}" >&2
        exit 1
    fi
fi

if [[ ! -x "${SNITCH_LLVM_BIN}/riscv32-unknown-elf-clang" ]]; then
    echo "Missing Snitch LLVM compiler: ${SNITCH_LLVM_BIN}/riscv32-unknown-elf-clang" >&2
    exit 1
fi

if [[ -d "${OCCAMY_PYTHON_VENV}" ]]; then
    export PATH="${SNITCH_LLVM_BIN}:${OCCAMY_PYTHON_VENV}/bin:${PATH}"
else
    export PATH="${SNITCH_LLVM_BIN}:${PATH}"
fi

export LLVM_BINROOT="${SNITCH_LLVM_BIN}/"
export RISCV_CFLAGS="-isystem ${SNITCH_NEWLIB}/include ${RISCV_CFLAGS:-}"
export RISCV_LDFLAGS="-L${SNITCH_NEWLIB}/lib -L${SNITCH_COMPILER_RT} ${RISCV_LDFLAGS:-}"
export SNITCH_ROOT
export SNITCH_TARGET
export SNITCH_CFG
export S0_DIR
export REPO_ROOT

echo "S0_DIR         = ${S0_DIR}"
echo "SNITCH_ROOT   = ${SNITCH_ROOT}"
echo "SNITCH_TARGET = ${SNITCH_TARGET}"
echo "SNITCH_CFG    = ${SNITCH_CFG}"
echo "LLVM_BINROOT  = ${LLVM_BINROOT}"
echo "PYTHON        = $(command -v python3)"
echo "NEWLIB        = ${SNITCH_NEWLIB}"
echo "COMPILER_RT   = ${SNITCH_COMPILER_RT}"
