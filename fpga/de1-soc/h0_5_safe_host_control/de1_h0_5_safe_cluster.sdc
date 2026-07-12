create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks
derive_clock_uncertainty

set loop_cut_cells [get_cells -hierarchical {*i_loop_cut}]
set loop_cut_count [get_collection_size $loop_cut_cells]
if {$loop_cut_count != 6} {
  post_message -type error "H0.7 expected exactly six active loop-cut cells, found $loop_cut_count"
}
set_disable_timing $loop_cut_cells
