#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
u3_dir=$(cd -- "${script_dir}/.." && pwd)
repo_root=$(cd -- "${u3_dir}/../../.." && pwd)
snitch_root="${repo_root}/platforms/occamy/deps/snitch_cluster"
cfg="${u3_dir}/cfg/one-core-integer.hjson"
generated="${u3_dir}/generated"
python="${repo_root}/.venv-occamy/bin/python"

if [[ ! -x "${python}" ]]; then
    echo "Missing ${python}; create the Occamy Python environment first." >&2
    exit 1
fi

mkdir -p "${generated}"

"${python}" "${snitch_root}/util/clustergen.py" \
    --clustercfg "${cfg}" \
    --outdir "${generated}" \
    --wrapper \
    --memories

"${python}" "${script_dir}/normalize_zero_ssr.py" \
    "${generated}/snitch_cluster_wrapper.sv"

bender -d "${snitch_root}" script genus \
    -t synthesis \
    -t snitch_cluster \
    -t disable_pmcs \
    > "${generated}/sources.genus.tcl"

printf 'Generated %s\n' "${generated}/snitch_cluster_wrapper.sv"
printf 'Generated %s\n' "${generated}/memories.json"
printf 'Generated %s\n' "${generated}/sources.genus.tcl"
