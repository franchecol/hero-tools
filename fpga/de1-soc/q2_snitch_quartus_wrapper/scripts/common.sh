#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S2_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
REPO_ROOT=$(git -C "${S2_DIR}" rev-parse --show-toplevel)
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
SNITCH_CFG="${S2_DIR}/cfg/one-core.hjson"
GENERATED_DIR="${S2_DIR}/generated"
PROJECT="de1_s2_snitch_quartus_wrapper"

export S2_DIR
export REPO_ROOT
export SNITCH_ROOT
export SNITCH_TARGET
export SNITCH_CFG
export GENERATED_DIR
export PROJECT

if [[ -z "${S2_COMMON_PRINTED:-}" ]]; then
    echo "S2_DIR         = ${S2_DIR}"
    echo "SNITCH_ROOT   = ${SNITCH_ROOT}"
    echo "SNITCH_TARGET = ${SNITCH_TARGET}"
    echo "SNITCH_CFG    = ${SNITCH_CFG}"
    echo "GENERATED_DIR = ${GENERATED_DIR}"
    export S2_COMMON_PRINTED=1
fi
