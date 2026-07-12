create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks
derive_clock_uncertainty

# Genus inserted six CKBD0 cells to mark pre-existing feedback timing cuts.
# Their Quartus lcell models preserve those markers through generic import.
set loop_cut_cells [get_cells -hierarchical {*i_loop_cut}]
if {[get_collection_size $loop_cut_cells] != 5} {
  post_message -type error "H0.4 expected exactly five active loop-cut cells"
}
set_disable_timing $loop_cut_cells
