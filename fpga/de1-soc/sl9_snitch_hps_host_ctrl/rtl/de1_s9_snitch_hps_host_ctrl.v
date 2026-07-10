module de1_s9_snitch_hps_host_ctrl (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    output wire [9:0] LEDR
);

    wire reset = ~KEY[0];

    s9_hps_snitch_system u_hps_snitch_system (
        .clk_clk     (CLOCK_50),
        .reset_reset (reset),
        .ledr_export (LEDR)
    );

endmodule
