#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

mkdir -p "${GENERATED_DIR}"

sed "s|@SNITCH_ROOT@|${SNITCH_ROOT}|g" \
    "${EXP_DIR}/source_list/snitch_cluster.flist-plus.in" \
    > "${GENERATED_DIR}/snitch_cluster.flist-plus"

python3 "${QSF_CONVERTER}" \
    "${GENERATED_DIR}/snitch_cluster.flist-plus" \
    "${GENERATED_DIR}/snitch_sources.qsf"

cp "${EXP_DIR}/quartus/${PROJECT}.qpf" "${GENERATED_DIR}/${PROJECT}.qpf"
sed "s|@EXP_DIR@|${EXP_DIR}|g" \
    "${EXP_DIR}/quartus/base.qsf" \
    > "${GENERATED_DIR}/base.qsf"
cat \
    "${GENERATED_DIR}/base.qsf" \
    "${GENERATED_DIR}/snitch_sources.qsf" \
    > "${GENERATED_DIR}/${PROJECT}.qsf"

echo "Generated ${GENERATED_DIR}/${PROJECT}.qpf"
echo "Generated ${GENERATED_DIR}/${PROJECT}.qsf"
echo "Generated ${GENERATED_DIR}/snitch_sources.qsf"
