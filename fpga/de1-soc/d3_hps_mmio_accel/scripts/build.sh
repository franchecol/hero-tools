#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

repo_root="$(git rev-parse --show-toplevel)"
d3_ip="${repo_root}/fpga/de1-soc/d3_hps_mmio_accel/ip/d3_mmio_regs"
project=de1_d3_hps_mmio_accel

neutralize_hps_sdram_sdc() {
  local sdc

  for sdc in \
    d3_hps_mmio_system/synthesis/submodules/hps_sdram_p0.sdc \
    db/ip/d3_hps_mmio_system/submodules/hps_sdram_p0.sdc; do
    if [[ -f "${sdc}" ]]; then
      : > "${sdc}"
    fi
  done
}

qsys-script \
  --search-path="${d3_ip},$" \
  --script=scripts/create_qsys.tcl

# Quartus 25.1 sometimes saves this derived HPS parameter as false even though
# the qsys script sets it. Force bridge-only mode before HDL generation.
perl -0pi -e 's/(name="quartus_ini_hps_ip_suppress_sdram_synth" value=")false(" \/>)/${1}true${2}/' \
  d3_hps_mmio_system.qsys

qsys-generate d3_hps_mmio_system.qsys \
  --synthesis=VERILOG \
  --search-path="${d3_ip},$" \
  --family="Cyclone V" \
  --part=5CSEMA5F31C6

# D3 does not export the HPS DDR pins. The Cyclone V HPS IP can still generate
# a stale SDRAM timing script that aborts fitting, so keep it empty for this
# lightweight-bridge-only experiment.
neutralize_hps_sdram_sdc

quartus_map --read_settings_files=on --write_settings_files=off "${project}" -c "${project}"
neutralize_hps_sdram_sdc
quartus_fit --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_asm --read_settings_files=off --write_settings_files=off "${project}" -c "${project}"
quartus_sta "${project}" -c "${project}"

quartus_cpf -c \
  "output_files/${project}.sof" \
  "output_files/${project}.rbf"
