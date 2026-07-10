module de1_s8_snitch_jtag_host_ctrl (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    output wire [9:0] LEDR
);

    wire reset = ~KEY[0];

    s8_jtag_system u_jtag_system (
        .clk_clk     (CLOCK_50),
        .reset_reset (reset),
        .ledr_export (LEDR)
    );

endmodule
