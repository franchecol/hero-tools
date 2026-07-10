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

python3 "${QSF_CONVERTER}" \
    "${GENERATED_DIR}/snitch_cluster.flist-plus" \
    "${GENERATED_DIR}/snitch_sources.qsf"

"${EXP_DIR}/scripts/make_patch_overlay.sh"

export ORIG_TC_SRAM="${TECH_CELLS_ROOT}/src/rtl/tc_sram.sv"
export PATCH_TC_SRAM="${PATCH_DIR}/tech_cells_generic/src/rtl/tc_sram.sv"
export ORIG_TC_SRAM_IMPL="${TECH_CELLS_ROOT}/src/rtl/tc_sram_impl.sv"
export PATCH_TC_SRAM_IMPL="${PATCH_DIR}/tech_cells_generic/src/rtl/tc_sram_impl.sv"
export ORIG_SNITCH_CLUSTER="${SNITCH_ROOT}/hw/snitch_cluster/src/snitch_cluster.sv"
export PATCH_SNITCH_CLUSTER="${PATCH_DIR}/snitch_cluster/src/snitch_cluster.sv"
export ORIG_SNITCH_ICACHE_LOOKUP="${SNITCH_ROOT}/hw/snitch_icache/src/snitch_icache_lookup.sv"
export PATCH_SNITCH_ICACHE_LOOKUP="${PATCH_DIR}/snitch_icache/src/snitch_icache_lookup.sv"

perl -0pi -e '
    s/\Q$ENV{ORIG_TC_SRAM}\E/$ENV{PATCH_TC_SRAM}/g;
    s/\Q$ENV{ORIG_TC_SRAM_IMPL}\E/$ENV{PATCH_TC_SRAM_IMPL}/g;
    s/\Q$ENV{ORIG_SNITCH_CLUSTER}\E/$ENV{PATCH_SNITCH_CLUSTER}/g;
    s/\Q$ENV{ORIG_SNITCH_ICACHE_LOOKUP}\E/$ENV{PATCH_SNITCH_ICACHE_LOOKUP}/g;
' "${GENERATED_DIR}/snitch_sources.qsf"

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

