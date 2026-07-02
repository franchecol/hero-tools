#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

export CXXFLAGS="${S1_HOST_CXXFLAGS:--include cstdint}"
export VERILATOR_ROOT="${S1_VERILATOR_ROOT:-/usr/share/verilator}"
export VLT_ROOT="${VERILATOR_ROOT}"

S1_DEFAULT_VLT_FLAGS=(
    --no-timing
    --no-assert
    -O0
    -fno-dfg
    --trace
    --unroll-count 1024
    -Wno-BLKANDNBLK
    -Wno-LITENDIAN
    -Wno-CASEINCOMPLETE
    -Wno-CMPCONST
    -Wno-WIDTH
    -Wno-WIDTHCONCAT
    -Wno-UNSIGNED
    -Wno-UNOPTFLAT
    -Wno-fatal
    -Wno-MODDUP
    -Wno-PINMISSING
    -Wno-IMPLICIT
    -Wno-SHORTREAL
    -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC
    -Wno-ASCRANGE
    -Wno-SELRANGE
    -Wno-STMTDLY
    -Wno-LATCH
)
S1_DEFAULT_VLT_FLAGS_TEXT="${S1_DEFAULT_VLT_FLAGS[*]}"

make -C "${SNITCH_TARGET}" \
    CFG_OVERRIDE="${SNITCH_CFG}" \
    "${SNITCH_TARGET}/generated/snitch_cluster_wrapper.sv" \
    "${SNITCH_TARGET}/generated/link.ld" \
    "${SNITCH_TARGET}/generated/memories.json" \
    "${SNITCH_TARGET}/generated/bootdata.cc"

make -C "${SNITCH_TARGET}" \
    VLT_ROOT="${VLT_ROOT}" \
    work-vlt/vlt/verilated_threads.o

make -C "${SNITCH_TARGET}" \
    CFG_OVERRIDE="${SNITCH_CFG}" \
    LDFLAGS="work-vlt/vlt/verilated_threads.o ${LDFLAGS:-}" \
    VLT_FLAGS="${S1_VLT_FLAGS:-${S1_DEFAULT_VLT_FLAGS_TEXT}}" \
    bin/snitch_cluster.vlt

echo "Built ${SNITCH_TARGET}/bin/snitch_cluster.vlt"
