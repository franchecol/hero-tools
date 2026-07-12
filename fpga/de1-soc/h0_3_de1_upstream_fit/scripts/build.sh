#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
h0_2_dir=$(cd -- "${h0_dir}/../h0_2_avalon_axi_bridge" && pwd)
project=de1_h0_3_upstream_cluster
system=h0_2_upstream_hps_system

neutralize_hps_sdram_sdc() {
  local sdc
  for sdc in \
    "${h0_dir}/${system}/synthesis/submodules/hps_sdram_p0.sdc" \
    "${h0_dir}/db/ip/${system}/submodules/hps_sdram_p0.sdc"; do
    if [[ -f "${sdc}" ]]; then
      : > "${sdc}"
    fi
  done
}

"${h0_2_dir}/scripts/test_adapter.sh"
"${h0_2_dir}/scripts/generate_qsys.sh"
"${script_dir}/generate_pll.sh"

rm -rf "${h0_dir}/${system}"
cp -a "${h0_2_dir}/qsys/${system}" "${h0_dir}/${system}"
cp "${h0_2_dir}/qsys/${system}.qsys" "${h0_dir}/${system}.qsys"

cd "${h0_dir}"
neutralize_hps_sdram_sdc
quartus_map --read_settings_files=on --write_settings_files=off "${project}" -c "${project}"
neutralize_hps_sdram_sdc
quartus_fit --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_asm --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_sta "${project}" -c "${project}"
if grep -q "Timing requirements not met" "output_files/${project}.sta.rpt"; then
  printf 'ERROR: Quartus timing requirements were not met.\n' >&2
  exit 1
fi
quartus_cpf -c "output_files/${project}.sof" "output_files/${project}.rbf"

grep -E "Fitter Status|Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|Total DSP Blocks|Total PLLs" \
  "output_files/${project}.fit.summary"
grep -E "Type  :|Slack :|TNS   :" "output_files/${project}.sta.summary"
