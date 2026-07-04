module de1_s13_snitch_hps_irq_done (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    output wire [9:0] LEDR
);

    wire reset = ~KEY[0];
    reg slow_clk_q = 1'b0;

    always @(posedge CLOCK_50 or posedge reset) begin
        if (reset) begin
            slow_clk_q <= 1'b0;
        end else begin
            slow_clk_q <= ~slow_clk_q;
        end
    end

    s13_hps_snitch_irq_system u_hps_snitch_system (
        .clk_clk     (slow_clk_q),
        .reset_reset (reset),
        .ledr_export (LEDR)
    );

endmodule
