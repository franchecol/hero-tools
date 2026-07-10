module de1_s2_snitch_quartus_wrapper (
    input  logic       CLOCK_50,
    input  logic [3:0] KEY,
    output logic [9:0] LEDR
);
    import snitch_cluster_pkg::*;

    logic rst_ni;
    assign rst_ni = KEY[0];

    logic [NrCores-1:0] irq_zero;
    assign irq_zero = '0;

    narrow_in_req_t   narrow_in_req;
    narrow_in_resp_t  narrow_in_resp;
    narrow_out_req_t  narrow_out_req;
    narrow_out_resp_t narrow_out_resp;
    wide_in_req_t     wide_in_req;
    wide_in_resp_t    wide_in_resp;
    wide_out_req_t    wide_out_req;
    wide_out_resp_t   wide_out_resp;

    assign narrow_in_req = '0;
    assign wide_in_req = '0;
    assign narrow_out_resp = '0;
    assign wide_out_resp = '0;

    snitch_cluster_wrapper i_snitch_cluster (
        .clk_i             (CLOCK_50),
        .rst_ni            (rst_ni),
        .debug_req_i       (irq_zero),
        .meip_i            (irq_zero),
        .mtip_i            (irq_zero),
        .msip_i            (irq_zero),
        .narrow_in_req_i   (narrow_in_req),
        .narrow_in_resp_o  (narrow_in_resp),
        .narrow_out_req_o  (narrow_out_req),
        .narrow_out_resp_i (narrow_out_resp),
        .wide_out_req_o    (wide_out_req),
        .wide_out_resp_i   (wide_out_resp),
        .wide_in_req_i     (wide_in_req),
        .wide_in_resp_o    (wide_in_resp)
    );

    assign LEDR[0] = narrow_out_req.aw_valid;
    assign LEDR[1] = narrow_out_req.w_valid;
    assign LEDR[2] = narrow_out_req.ar_valid;
    assign LEDR[3] = wide_out_req.aw_valid;
    assign LEDR[4] = wide_out_req.w_valid;
    assign LEDR[5] = wide_out_req.ar_valid;
    assign LEDR[6] = narrow_in_resp.aw_ready;
    assign LEDR[7] = wide_in_resp.aw_ready;
    assign LEDR[8] = rst_ni;
    assign LEDR[9] = 1'b1;
endmodule

