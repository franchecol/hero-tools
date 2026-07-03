create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
create_generated_clock -name S11_QSYS_CLK -source [get_ports {CLOCK_50}] -divide_by 2 [get_pins {slow_clk_q|q}]

# slow_clk_q is the fabric divider flop that creates S11_QSYS_CLK.  Quartus can
# otherwise analyze its own Q->D feedback as if it were launched by the generated
# clock and captured by CLOCK_50, creating a false hold violation on the divider.
set_false_path -from [get_clocks {S11_QSYS_CLK}] -to [get_registers {slow_clk_q}]

derive_clock_uncertainty
