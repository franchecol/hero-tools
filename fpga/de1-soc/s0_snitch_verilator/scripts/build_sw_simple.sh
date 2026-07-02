#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

make -C "${SNITCH_TARGET}" \
    CFG_OVERRIDE="${SNITCH_CFG}" \
    sw/runtime/common/snitch_cluster_cfg.h \
    sw/runtime/common/snitch_cluster_addrmap.h \
    sw/runtime/common/snitch_cluster_peripheral.h

make -C "${SNITCH_TARGET}/sw/runtime/rtl"

make -C "${SNITCH_TARGET}/sw/tests" \
    "${SNITCH_TARGET}/sw/tests/build/simple.elf"

echo "Built ${SNITCH_TARGET}/sw/tests/build/simple.elf"

