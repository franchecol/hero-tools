#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s19_dir=$(cd -- "${script_dir}/.." && pwd)
lab_host=${LAB_HOST:-143.107.161.165}
lab_port=${LAB_PORT:-2223}
lab_user=${LAB_USER:-francotv}
remote="${lab_user}@${lab_host}"
remote_dir='snitch_gatelevel_lab/s19'

"${script_dir}/build_sw.sh"

scp -P "${lab_port}" \
    "${s19_dir}/generated/rom_words.svh" \
    "${s19_dir}/rtl/de1_s19_genus_snitch_data_ram.sv" \
    "${s19_dir}/tb/de1_s19_genus_snitch_data_ram_tb.sv" \
    "${remote}:~/${remote_dir}/"

ssh -p "${lab_port}" "${remote}" \
    "cd ~/${remote_dir} && \
     export PATH=/local/tools_sampasim1/mgc/questasim-2019.4/questasim/bin:\$PATH && \
     export LM_LICENSE_FILE=5285@license && \
     rm -rf work && vlib work && \
     vlog +incdir+. \
       /local/users/tsmc65/Base_PDK/digital/Front_End/verilog/tcbn65lp_200a/tcbn65lp.v \
       snitch_mem_genus_netlist.v de1_s19_genus_snitch_data_ram.sv \
       de1_s19_genus_snitch_data_ram_tb.sv 2>&1 | tee snitch_mem_gate_vlog.log && \
     vsim -c de1_s19_genus_snitch_data_ram_tb \
       -do 'run -all; quit -f' 2>&1 | tee snitch_mem_gate_vsim.log"
