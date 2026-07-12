#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
system=h0_5_safe_hps_system
ip_dir="${h0_dir}/ip/h0_5_safe_cluster"

rm -rf "${h0_dir}/qsys"
mkdir -p "${h0_dir}/qsys"
cd "${h0_dir}/qsys"

qsys-script \
  --script="${script_dir}/create_qsys.tcl" \
  --search-path="${ip_dir},$"

perl -0pi -e 's/(name="quartus_ini_hps_ip_suppress_sdram_synth" value=")false(" \/>)/${1}true${2}/' \
  "${system}.qsys"

qsys-generate "${system}.qsys" \
  --synthesis=VERILOG \
  --search-path="${ip_dir},$" \
  --family="Cyclone V" \
  --part=5CSEMA5F31C6

test -f "${system}/synthesis/${system}.qip"
printf 'H0.5_QSYS_PASS\n'
