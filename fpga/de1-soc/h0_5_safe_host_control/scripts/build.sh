#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
project=de1_h0_5_safe_cluster
system=h0_5_safe_hps_system

neutralize_hps_sdram_sdc() {
  local sdc
  for sdc in \
    "${h0_dir}/qsys/${system}/synthesis/submodules/hps_sdram_p0.sdc" \
    "${h0_dir}/db/ip/${system}/submodules/hps_sdram_p0.sdc"; do
    [[ ! -f "${sdc}" ]] || : > "${sdc}"
  done
}

"${script_dir}/test_control.sh"
"${h0_dir}/../h0_7_observable_boot/scripts/build_firmware.sh"
"${h0_dir}/../h0_7_observable_boot/scripts/test_signature_sink.sh"
"${h0_dir}/../h2_host_program_memory/scripts/test_boot_ram.sh"
"${script_dir}/generate_qsys.sh"
"${script_dir}/generate_pll.sh"

cd "${h0_dir}"
neutralize_hps_sdram_sdc
quartus_map --read_settings_files=on --write_settings_files=off "${project}" -c "${project}"
neutralize_hps_sdram_sdc
quartus_fit --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_asm --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_sta "${project}" -c "${project}"
if grep -q "Design contains combinational loop\|Timing requirements not met" \
    "output_files/${project}.sta.rpt"; then
  printf 'ERROR: H0.5 timing validation failed.\n' >&2
  exit 1
fi
quartus_cpf -c "output_files/${project}.sof" "output_files/${project}.rbf"
