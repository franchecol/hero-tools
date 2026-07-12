module de1_h0_5_safe_cluster (
  input  wire       CLOCK_50,
  input  wire [3:0] KEY,
  output wire [9:0] LEDR
);
  wire cluster_clk;
  wire pll_locked;
  wire pll_reset = ~KEY[0];
  wire system_reset = ~KEY[0] | ~pll_locked;

  cluster_pll i_cluster_pll (
    .refclk(CLOCK_50), .rst(pll_reset),
    .outclk_0(cluster_clk), .locked(pll_locked)
  );

  h0_5_safe_hps_system i_hps_cluster (
    .clk_clk(cluster_clk), .reset_reset(system_reset)
  );

  assign LEDR = {8'b0, system_reset, pll_locked};
endmodule
