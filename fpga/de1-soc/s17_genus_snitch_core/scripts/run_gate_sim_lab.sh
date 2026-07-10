#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/snitch_gatelevel_lab/s17"

export PATH=/local/tools_sampasim1/mgc/questasim-2019.4/questasim/bin:$PATH
export LM_LICENSE_FILE=5285@license

cell_model=/local/users/tsmc65/Base_PDK/digital/Front_End/verilog/tcbn65lp_200a/tcbn65lp.v

rm -rf work
vlib work
vlog "$cell_model" snitch_core_genus_netlist.v snitch_core_gate_tb.sv \
    2>&1 | tee snitch_core_gate_vlog.log
vsim -c snitch_core_gate_tb -do 'run -all; quit -f' \
    2>&1 | tee snitch_core_gate_vsim.log
