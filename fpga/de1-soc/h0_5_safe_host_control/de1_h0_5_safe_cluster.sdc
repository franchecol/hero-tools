create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks
derive_clock_uncertainty

set loop_cut_cells [get_cells -hierarchical {*i_loop_cut}]
set loop_cut_count [get_collection_size $loop_cut_cells]
if {$loop_cut_count < 5 || $loop_cut_count > 6} {
  post_message -type error "Expected five or six active imported loop-cut cells, found $loop_cut_count"
} elseif {$loop_cut_count == 5} {
  post_message -type info "One imported loop-cut cell was optimized away; constraining the five active cells"
}
set_disable_timing $loop_cut_cells
