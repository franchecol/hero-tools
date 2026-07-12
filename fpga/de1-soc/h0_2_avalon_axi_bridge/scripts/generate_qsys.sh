#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
u4_dir=$(cd -- "${h0_dir}/../u4_cyclone_memory_boundary" && pwd)
ip_dir="${h0_dir}/ip/h0_2_cluster_component"
qsys_dir="${h0_dir}/qsys"

"${u4_dir}/scripts/prepare_quartus_netlist.sh"
mkdir -p "${qsys_dir}"
cd "${qsys_dir}"

qsys-script --search-path="${ip_dir},$" --script="${h0_dir}/scripts/create_qsys.tcl"

perl -0pi -e 's/(name="quartus_ini_hps_ip_suppress_sdram_synth" value=")false(" \/>)/${1}true${2}/' \
    h0_2_upstream_hps_system.qsys

qsys-generate h0_2_upstream_hps_system.qsys \
    --synthesis=VERILOG \
    --search-path="${ip_dir},$" \
    --family="Cyclone V" \
    --part=5CSEMA5F31C6

test -f h0_2_upstream_hps_system/synthesis/h0_2_upstream_hps_system.v
printf 'Generated H0.2 HPS/cluster system successfully.\n'
