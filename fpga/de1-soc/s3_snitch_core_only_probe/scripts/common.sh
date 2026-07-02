#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S3_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(git -C "${S3_DIR}" rev-parse --show-toplevel)
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

GENERATED_DIR="${S3_DIR}/generated"
SV2V="${SV2V:-sv2v}"
YOSYS="${YOSYS:-yosys}"

export S3_DIR
export REPO_ROOT
export SNITCH_ROOT
export COMMON_CELLS_ROOT
export GENERATED_DIR
export SV2V
export YOSYS

echo "S3_DIR            = ${S3_DIR}"
echo "SNITCH_ROOT       = ${SNITCH_ROOT}"
echo "COMMON_CELLS_ROOT = ${COMMON_CELLS_ROOT}"
echo "GENERATED_DIR     = ${GENERATED_DIR}"
echo "SV2V              = ${SV2V}"
echo "YOSYS             = ${YOSYS}"
