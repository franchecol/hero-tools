set TOP snitch_genus_probe
set ROOT [file normalize [file dirname [info script]]]
set SNITCH_ROOT [file join $ROOT snitch_cluster]
set COMMON_ROOT [file join $ROOT common_cells]
set LIB_FILE /local/users/tsmc65/Base_PDK/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_200a/tcbn65lptc.lib

set_attribute library $LIB_FILE /
set_attribute init_hdl_search_path [list [file join $COMMON_ROOT include]] /

set SOURCES [list \
  [file join $ROOT snitch_core_shims.sv] \
  [file join $SNITCH_ROOT hw/snitch/src/snitch_pma_pkg.sv] \
  [file join $SNITCH_ROOT hw/snitch/src/riscv_instr.sv] \
  [file join $SNITCH_ROOT hw/snitch/src/snitch_pkg.sv] \
  [file join $COMMON_ROOT src/fifo_v3.sv] \
  [file join $SNITCH_ROOT hw/snitch/src/snitch_regfile_ff.sv] \
  [file join $SNITCH_ROOT hw/snitch/src/snitch_lsu.sv] \
  [file join $SNITCH_ROOT hw/snitch/src/snitch_l0_tlb.sv] \
  [file join $SNITCH_ROOT hw/snitch/src/snitch.sv] \
  [file join $ROOT snitch_genus_probe.sv] \
]

read_hdl -sv -define SYNTHESIS $SOURCES
elaborate $TOP
check_design -unresolved

write_hdl > snitch_core_elaborated.v
report gates > snitch_core_elaborated_gates.rpt

syn_generic
write_hdl > snitch_core_generic_netlist.v
report gates > snitch_core_generic_gates.rpt

syn_map
write_hdl > snitch_core_genus_netlist.v
report gates > snitch_core_mapped_gates.rpt
report area > snitch_core_area.rpt
report timing > snitch_core_timing.rpt

exit
