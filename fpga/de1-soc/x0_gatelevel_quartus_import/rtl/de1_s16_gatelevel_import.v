module de1_s16_gatelevel_import (
    input  wire       CLOCK_50,
    input  wire [0:0] KEY,
    input  wire [0:0] SW,
    output wire [9:0] LEDR
);

    wire [7:0] count;
    wire       rst_n = KEY[0];
    wire       enable = SW[0];

    toy_counter u_counter (
        .clk_i   (CLOCK_50),
        .rst_ni  (rst_n),
        .en_i    (enable),
        .count_o (count)
    );

    assign LEDR[7:0] = count;
    assign LEDR[8] = enable;
    assign LEDR[9] = rst_n;

endmodule
