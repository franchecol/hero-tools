#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

repo_root="$(git rev-parse --show-toplevel)"
s8_dir="${repo_root}/fpga/de1-soc/s8_snitch_jtag_host_ctrl"
s9_ip="${repo_root}/fpga/de1-soc/s9_snitch_hps_host_ctrl/ip/s9_snitch_ctrl"
project=de1_s9_snitch_hps_host_ctrl
system=s9_hps_snitch_system

neutralize_hps_sdram_sdc() {
  local sdc

  for sdc in \
    "${system}/synthesis/submodules/hps_sdram_p0.sdc" \
    "db/ip/${system}/submodules/hps_sdram_p0.sdc"; do
    if [[ -f "${sdc}" ]]; then
      : > "${sdc}"
    fi
  done
}

"${s8_dir}/scripts/run_sv2v_probe.sh"
mkdir -p generated
cp "${s8_dir}/generated/snitch_host_ctrl_core.v" generated/snitch_host_ctrl_core.v
cp "${s8_dir}/generated/rom_manifest.json" generated/rom_manifest.json

qsys-script \
  --search-path="${s9_ip},$" \
  --script=scripts/create_qsys.tcl

# Quartus 25.1 sometimes saves this derived HPS parameter as false even though
# the qsys script sets it. Force bridge-only mode before HDL generation.
perl -0pi -e 's/(name="quartus_ini_hps_ip_suppress_sdram_synth" value=")false(" \/>)/${1}true${2}/' \
  "${system}.qsys"

qsys-generate "${system}.qsys" \
  --synthesis=VERILOG \
  --search-path="${s9_ip},$" \
  --family="Cyclone V" \
  --part=5CSEMA5F31C6

# S9 uses only the lightweight bridge. Do not run stale HPS SDRAM constraints
# generated for unexported DDR pins.
neutralize_hps_sdram_sdc

quartus_map --read_settings_files=on --write_settings_files=off "${project}" -c "${project}"
neutralize_hps_sdram_sdc
quartus_fit --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_asm --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_sta "${project}" -c "${project}"

quartus_cpf -c \
  "output_files/${project}.sof" \
  "output_files/${project}.rbf"
