module de1_d3_hps_mmio_accel (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    output wire [9:0] LEDR,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5
);

    wire key_reset = ~KEY[0];

    d3_hps_mmio_system u_mmio_system (
        .clk_clk      (CLOCK_50),
        .reset_reset  (key_reset),
        .ledr_export  (LEDR),
        .hex0_export  (HEX0),
        .hex1_export  (HEX1),
        .hex2_export  (HEX2),
        .hex3_export  (HEX3),
        .hex4_export  (HEX4),
        .hex5_export  (HEX5)
    );

endmodule
