#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EXP_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(git -C "${EXP_DIR}" rev-parse --show-toplevel)
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

TECH_CELLS_ROOT=$(
    find "${SNITCH_ROOT}/.bender/git/checkouts" \
        -maxdepth 1 \
        -type d \
        -name 'tech_cells_generic-*' \
        | sort \
        | tail -n 1
)

if [[ -z "${TECH_CELLS_ROOT}" || ! -d "${TECH_CELLS_ROOT}/src/rtl" ]]; then
    echo "Could not find tech_cells_generic checkout under ${SNITCH_ROOT}/.bender/git/checkouts" >&2
    exit 1
fi

SNITCH_TARGET="${SNITCH_ROOT}/target/snitch_cluster"
SNITCH_CFG="${REPO_ROOT}/fpga/de1-soc/s2_snitch_quartus_wrapper/cfg/one-core.hjson"
GENERATED_DIR="${EXP_DIR}/generated"
PATCH_DIR="${GENERATED_DIR}/patches"
PROJECT="de1_s2_2_snitch_patch_overlay"
QSF_CONVERTER="${REPO_ROOT}/fpga/de1-soc/s2_snitch_quartus_wrapper/scripts/flist_plus_to_qsf.py"

export EXP_DIR
export REPO_ROOT
export SNITCH_ROOT
export TECH_CELLS_ROOT
export SNITCH_TARGET
export SNITCH_CFG
export GENERATED_DIR
export PATCH_DIR
export PROJECT
export QSF_CONVERTER

if [[ -z "${S2_2_COMMON_PRINTED:-}" ]]; then
    echo "EXP_DIR         = ${EXP_DIR}"
    echo "SNITCH_ROOT    = ${SNITCH_ROOT}"
    echo "TECH_CELLS_ROOT= ${TECH_CELLS_ROOT}"
    echo "SNITCH_TARGET  = ${SNITCH_TARGET}"
    echo "SNITCH_CFG     = ${SNITCH_CFG}"
    echo "GENERATED_DIR  = ${GENERATED_DIR}"
    export S2_2_COMMON_PRINTED=1
fi

