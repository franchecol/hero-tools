#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
u4_dir=$(cd -- "${script_dir}/.." && pwd)
repo_root=$(cd -- "${u4_dir}/../../.." && pwd)
u3_dir="${repo_root}/fpga/de1-soc/u3_genus_snitch_cluster"
snitch_root="${repo_root}/platforms/occamy/deps/snitch_cluster"
generated="${u4_dir}/generated"

"${u3_dir}/scripts/generate.sh"
mkdir -p "${generated}"
cp "${u3_dir}/generated/snitch_cluster_wrapper.sv" "${generated}/"
cp "${u3_dir}/generated/memories.json" "${generated}/"

bender -d "${snitch_root}" script genus \
    -t synthesis \
    -t snitch_cluster \
    -t disable_pmcs \
    -t tech_cells_generic_exclude_tc_sram \
    > "${generated}/sources.genus.tcl"

if rg -q '/tc_sram(_impl)?\.sv' "${generated}/sources.genus.tcl"; then
    echo "Generic SRAM implementation remained in the Genus manifest." >&2
    exit 1
fi
