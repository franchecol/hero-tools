set TOP toy_counter
set LIB_FILE /local/users/tsmc65/Base_PDK/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_200a/tcbn65lptc.lib

set_attribute library $LIB_FILE /

read_hdl -sv toy_counter.sv
elaborate $TOP
check_design

syn_generic
syn_map

write_hdl > toy_counter_genus_netlist.v
report_area > toy_counter_area.rpt
report_timing > toy_counter_timing.rpt

exit
