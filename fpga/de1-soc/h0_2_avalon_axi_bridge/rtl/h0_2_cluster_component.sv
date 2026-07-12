module h0_2_cluster_component_core #(
  parameter int unsigned AvalonAddrWidth = 16
) (
  input  logic                       clk,
  input  logic                       reset,
  input  logic                       cluster_hold_reset,
  input  logic [AvalonAddrWidth-1:0] avs_address,
  input  logic                       avs_read,
  output logic [31:0]                avs_readdata,
  input  logic                       avs_write,
  input  logic [31:0]                avs_writedata,
  input  logic [3:0]                 avs_byteenable,
  output logic                       avs_waitrequest
);
  logic r_ready, ar_valid, ar_ready, r_valid, r_last;
  logic [31:0] ar_addr;
  logic [2:0] ar_size;
  logic [63:0] r_data;
  logic [1:0] r_resp, r_id;
  logic b_ready, w_valid, w_ready, w_last, aw_valid, aw_ready, b_valid;
  logic [63:0] w_data;
  logic [7:0] w_strb;
  logic [31:0] aw_addr;
  logic [2:0] aw_size;
  logic [1:0] b_resp, b_id;

  avalon_to_narrow_axi #(.AvalonAddrWidth(AvalonAddrWidth)) i_bridge (
    .clk_i(clk), .rst_i(reset),
    .avs_address_i(avs_address), .avs_read_i(avs_read),
    .avs_readdata_o(avs_readdata), .avs_write_i(avs_write),
    .avs_writedata_i(avs_writedata), .avs_byteenable_i(avs_byteenable),
    .avs_waitrequest_o(avs_waitrequest),
    .axi_r_ready_o(r_ready), .axi_ar_valid_o(ar_valid),
    .axi_ar_addr_o(ar_addr), .axi_ar_size_o(ar_size),
    .axi_ar_ready_i(ar_ready), .axi_r_valid_i(r_valid),
    .axi_r_data_i(r_data), .axi_r_resp_i(r_resp),
    .axi_b_ready_o(b_ready), .axi_w_valid_o(w_valid),
    .axi_w_data_o(w_data), .axi_w_strb_o(w_strb), .axi_w_last_o(w_last),
    .axi_aw_valid_o(aw_valid), .axi_aw_addr_o(aw_addr),
    .axi_aw_size_o(aw_size), .axi_aw_ready_i(aw_ready),
    .axi_w_ready_i(w_ready), .axi_b_valid_i(b_valid), .axi_b_resp_i(b_resp)
  );

  h0_1_upstream_cluster_shell i_cluster_shell (
    .clk_i(clk), .rst_ni(~reset & ~cluster_hold_reset),
    .host_r_ready_i(r_ready), .host_ar_valid_i(ar_valid),
    .host_ar_addr_i(ar_addr), .host_ar_size_i(ar_size), .host_ar_id_i(2'b00),
    .host_ar_ready_o(ar_ready), .host_r_valid_o(r_valid),
    .host_r_data_o(r_data), .host_r_resp_o(r_resp), .host_r_id_o(r_id),
    .host_r_last_o(r_last), .host_b_ready_i(b_ready),
    .host_aw_valid_i(aw_valid), .host_aw_addr_i(aw_addr),
    .host_aw_size_i(aw_size), .host_aw_id_i(2'b00),
    .host_aw_ready_o(aw_ready), .host_w_valid_i(w_valid),
    .host_w_data_i(w_data), .host_w_strb_i(w_strb), .host_w_last_i(w_last),
    .host_w_ready_o(w_ready), .host_b_valid_o(b_valid),
    .host_b_resp_o(b_resp), .host_b_id_o(b_id)
  );
endmodule
