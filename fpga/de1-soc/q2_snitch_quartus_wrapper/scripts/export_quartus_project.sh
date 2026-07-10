#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

mkdir -p "${GENERATED_DIR}"

make -C "${SNITCH_TARGET}" \
    CFG_OVERRIDE="${SNITCH_CFG}" \
    "${SNITCH_TARGET}/generated/snitch_cluster_wrapper.sv" \
    "${SNITCH_TARGET}/generated/memories.json"

(
    cd "${SNITCH_ROOT}"
    bender script flist-plus -t rtl -t snitch_cluster
) > "${GENERATED_DIR}/snitch_cluster.flist-plus"

python3 "${S2_DIR}/scripts/flist_plus_to_qsf.py" \
    "${GENERATED_DIR}/snitch_cluster.flist-plus" \
    "${GENERATED_DIR}/snitch_sources.qsf"

cp "${S2_DIR}/quartus/${PROJECT}.qpf" "${GENERATED_DIR}/${PROJECT}.qpf"
sed "s|@S2_DIR@|${S2_DIR}|g" \
    "${S2_DIR}/quartus/base.qsf" \
    > "${GENERATED_DIR}/base.qsf"
cat \
    "${GENERATED_DIR}/base.qsf" \
    "${GENERATED_DIR}/snitch_sources.qsf" \
    > "${GENERATED_DIR}/${PROJECT}.qsf"

echo "Generated ${GENERATED_DIR}/${PROJECT}.qpf"
echo "Generated ${GENERATED_DIR}/${PROJECT}.qsf"
echo "Generated ${GENERATED_DIR}/snitch_sources.qsf"
