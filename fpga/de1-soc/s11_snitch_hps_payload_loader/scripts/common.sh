#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S11_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(git -C "${S11_DIR}" rev-parse --show-toplevel)
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

if [[ -z "${SNITCH_ROOT}" || ! -d "${SNITCH_ROOT}/hw/snitch/src" ]]; then
    echo "Could not find Snitch cluster checkout under ${OCCAMY_DIR}/.bender/git/checkouts" >&2
    exit 1
fi

COMMON_CELLS_ROOT=$(
    find "${SNITCH_ROOT}/.bender/git/checkouts" \
        -maxdepth 1 \
        -type d \
        -name 'common_cells-*' \
        | sort \
        | tail -n 1
)

if [[ -z "${COMMON_CELLS_ROOT}" || ! -d "${COMMON_CELLS_ROOT}/include" ]]; then
    echo "Could not find common_cells checkout under ${SNITCH_ROOT}/.bender/git/checkouts" >&2
    exit 1
fi

GENERATED_DIR="${S11_DIR}/generated"
SW_BUILD_DIR="${GENERATED_DIR}/sw"
PROJECT="de1_s11_snitch_hps_payload_loader"
QSYS_SYSTEM="s11_hps_snitch_system"
SV2V="${SV2V:-sv2v}"
YOSYS="${YOSYS:-yosys}"
RISCV_PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf}"
S11_PAYLOAD_SRC="${S11_PAYLOAD_SRC:-${S11_DIR}/sw/payload_sum.S}"
S11_PAYLOAD_MAX_WORDS="${S11_PAYLOAD_MAX_WORDS:-16}"

if ! command -v "${RISCV_PREFIX}-gcc" >/dev/null 2>&1; then
    if command -v riscv64-elf-gcc >/dev/null 2>&1; then
        RISCV_PREFIX="riscv64-elf"
    else
        echo "Could not find ${RISCV_PREFIX}-gcc or riscv64-elf-gcc" >&2
        exit 1
    fi
fi

for tool in gcc objcopy objdump nm; do
    if ! command -v "${RISCV_PREFIX}-${tool}" >/dev/null 2>&1; then
        echo "Could not find ${RISCV_PREFIX}-${tool}" >&2
        exit 1
    fi
done

export S11_DIR
export REPO_ROOT
export OCCAMY_DIR
export SNITCH_ROOT
export COMMON_CELLS_ROOT
export GENERATED_DIR
export SW_BUILD_DIR
export PROJECT
export QSYS_SYSTEM
export SV2V
export YOSYS
export RISCV_PREFIX
export S11_PAYLOAD_SRC
export S11_PAYLOAD_MAX_WORDS

echo "S11_DIR                = ${S11_DIR}"
echo "SNITCH_ROOT            = ${SNITCH_ROOT}"
echo "COMMON_CELLS_ROOT      = ${COMMON_CELLS_ROOT}"
echo "GENERATED_DIR          = ${GENERATED_DIR}"
echo "SW_BUILD_DIR           = ${SW_BUILD_DIR}"
echo "PROJECT                = ${PROJECT}"
echo "QSYS_SYSTEM            = ${QSYS_SYSTEM}"
echo "SV2V                   = ${SV2V}"
echo "YOSYS                  = ${YOSYS}"
echo "RISCV_PREFIX           = ${RISCV_PREFIX}"
echo "S11_PAYLOAD_SRC        = ${S11_PAYLOAD_SRC}"
echo "S11_PAYLOAD_MAX_WORDS  = ${S11_PAYLOAD_MAX_WORDS}"
