module de1_s10_snitch_hps_data_input (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    output wire [9:0] LEDR
);

    wire reset = ~KEY[0];

    s10_hps_snitch_system u_hps_snitch_system (
        .clk_clk     (CLOCK_50),
        .reset_reset (reset),
        .ledr_export (LEDR)
    );

endmodule
