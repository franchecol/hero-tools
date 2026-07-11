#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
u3_dir=$(cd -- "${script_dir}/.." && pwd)
lab_host=${LAB_HOST:-143.107.161.165}
lab_port=${LAB_PORT:-2223}
lab_user=${LAB_USER:-francotv}
remote="${lab_user}@${lab_host}"
remote_dir='snitch_gatelevel_lab/u3'

"${script_dir}/generate.sh"

ssh -p "${lab_port}" "${remote}" "mkdir -p ~/${remote_dir}/generated"

scp -P "${lab_port}" \
    "${u3_dir}/cfg/one-core-integer.hjson" \
    "${remote}:~/${remote_dir}/one-core-integer.hjson"
scp -P "${lab_port}" \
    "${u3_dir}/lab/run_genus.tcl" \
    "${remote}:~/${remote_dir}/run_genus.tcl"
scp -P "${lab_port}" \
    "${u3_dir}/generated/snitch_cluster_wrapper.sv" \
    "${u3_dir}/generated/memories.json" \
    "${remote}:~/${remote_dir}/generated/"

ssh -p "${lab_port}" "${remote}" \
    "cd ~/${remote_dir} && \
     mkdir -p ~/snitch_gatelevel_lab/s17/snitch_cluster/target/snitch_cluster/generated && \
     cp generated/snitch_cluster_wrapper.sv \
       ~/snitch_gatelevel_lab/s17/snitch_cluster/target/snitch_cluster/generated/snitch_cluster_wrapper.sv && \
     ~/bin/bender -d ~/snitch_gatelevel_lab/s17/snitch_cluster script genus \
       -t synthesis -t snitch_cluster -t disable_pmcs \
       > generated/sources.genus.tcl && \
     export LM_LICENSE_FILE=5280@license CDS_LIC_FILE=5280@license && \
     /local/tools/GENUS2118/bin/genus -no_gui \
       -files run_genus.tcl 2>&1 | tee genus.log"
