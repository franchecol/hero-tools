set TOP de1_u3_snitch_cluster_wrapper
set ROOT [file normalize [file dirname [info script]]]
set LIB_FILE /local/users/tsmc65/Base_PDK/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_200a/tcbn65lptc.lib

set_db library $LIB_FILE
read_hdl -language sv [file join $ROOT tc_sram_impl_genus_bb.sv]
source [file join $ROOT generated sources.genus.tcl]

elaborate $TOP
check_design -unresolved
write_hdl > de1_u4_cluster_elaborated.v
report gates > de1_u4_cluster_elaborated_gates.rpt

syn_generic
write_hdl > de1_u4_cluster_generic.v
report gates > de1_u4_cluster_generic_gates.rpt
report area > de1_u4_cluster_generic_area.rpt

exit
