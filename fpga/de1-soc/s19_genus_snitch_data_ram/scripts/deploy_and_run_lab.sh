#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s19_dir=$(cd -- "${script_dir}/.." && pwd)
s17_dir=$(cd -- "${s19_dir}/../s17_genus_snitch_core" && pwd)
lab_host=${LAB_HOST:-143.107.161.165}
lab_port=${LAB_PORT:-2223}
lab_user=${LAB_USER:-francotv}
remote="${lab_user}@${lab_host}"
remote_dir='snitch_gatelevel_lab/s19'

"${script_dir}/build_sw.sh"

ssh -p "${lab_port}" "${remote}" \
    "mkdir -p ~/${remote_dir} && \
     ln -sfn ../s17/snitch_cluster ~/${remote_dir}/snitch_cluster && \
     ln -sfn ../s17/common_cells ~/${remote_dir}/common_cells"

scp -P "${lab_port}" \
    "${s19_dir}/lab/genus_snitch_mem.tcl" \
    "${s19_dir}/lab/snitch_genus_mem_probe.sv" \
    "${s17_dir}/lab/snitch_core_shims.sv" \
    "${remote}:~/${remote_dir}/"

ssh -p "${lab_port}" "${remote}" \
    "cd ~/${remote_dir} && \
     export LM_LICENSE_FILE=5280@license CDS_LIC_FILE=5280@license && \
     /local/tools/GENUS2118/bin/genus -no_gui -legacy_ui \
       -files genus_snitch_mem.tcl 2>&1 | tee genus_snitch_mem.log"
