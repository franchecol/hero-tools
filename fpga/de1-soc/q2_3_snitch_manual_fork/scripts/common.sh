#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EXP_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(git -C "${EXP_DIR}" rev-parse --show-toplevel)

SNITCH_ROOT="${EXP_DIR}/snitch_cluster"
SNITCH_TARGET="${SNITCH_ROOT}/target/snitch_cluster"
SNITCH_CFG="${EXP_DIR}/cfg/one-core.hjson"
GENERATED_DIR="${EXP_DIR}/generated"
PROJECT="de1_s2_3_snitch_manual_fork"
QSF_CONVERTER="${REPO_ROOT}/fpga/de1-soc/q2_snitch_quartus_wrapper/scripts/flist_plus_to_qsf.py"

if [[ ! -d "${SNITCH_TARGET}" ]]; then
    echo "Could not find manual Snitch fork target at ${SNITCH_TARGET}" >&2
    exit 1
fi

export EXP_DIR
export REPO_ROOT
export SNITCH_ROOT
export SNITCH_TARGET
export SNITCH_CFG
export GENERATED_DIR
export PROJECT
export QSF_CONVERTER

if [[ -z "${S2_3_COMMON_PRINTED:-}" ]]; then
    echo "EXP_DIR        = ${EXP_DIR}"
    echo "SNITCH_ROOT   = ${SNITCH_ROOT}"
    echo "SNITCH_TARGET = ${SNITCH_TARGET}"
    echo "SNITCH_CFG    = ${SNITCH_CFG}"
    echo "GENERATED_DIR = ${GENERATED_DIR}"
    export S2_3_COMMON_PRINTED=1
fi

