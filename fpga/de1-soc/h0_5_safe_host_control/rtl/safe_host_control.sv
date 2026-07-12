module safe_host_control #(
  parameter int unsigned AvalonAddrWidth = 16,
  parameter logic [31:0] BlockId = 32'h4830_0005,
  parameter logic [AvalonAddrWidth-1:0] ClusterBaseWord = 16'h0400
) (
  input  logic                       clk_i,
  input  logic                       rst_i,
  input  logic                       pll_locked_i,
  input  logic                       boot_fetch_seen_i,

  input  logic [AvalonAddrWidth-1:0] avs_address_i,
  input  logic                       avs_read_i,
  output logic [31:0]                avs_readdata_o,
  input  logic                       avs_write_i,
  input  logic [31:0]                avs_writedata_i,
  input  logic [3:0]                 avs_byteenable_i,
  output logic                       avs_waitrequest_o,

  output logic                       cluster_hold_reset_o,
  output logic [AvalonAddrWidth-1:0] cluster_address_o,
  output logic                       cluster_read_o,
  input  logic [31:0]                cluster_readdata_i,
  output logic                       cluster_write_o,
  output logic [31:0]                cluster_writedata_o,
  output logic [3:0]                 cluster_byteenable_o,
  input  logic                       cluster_waitrequest_i
);
  logic cluster_selected;
  logic release_cluster_q;

  assign cluster_selected = avs_address_i >= ClusterBaseWord;
  assign cluster_address_o = avs_address_i - ClusterBaseWord;
  assign cluster_read_o = avs_read_i && cluster_selected;
  assign cluster_write_o = avs_write_i && cluster_selected;
  assign cluster_writedata_o = avs_writedata_i;
  assign cluster_byteenable_o = avs_byteenable_i;
  assign cluster_hold_reset_o = ~release_cluster_q;

  always_comb begin
    avs_readdata_o = 32'h0000_0000;
    avs_waitrequest_o = 1'b0;
    if (cluster_selected) begin
      avs_readdata_o = cluster_readdata_i;
      avs_waitrequest_o = cluster_waitrequest_i;
    end else begin
      case (avs_address_i)
        0: avs_readdata_o = BlockId;
        1: avs_readdata_o = {31'b0, release_cluster_q};
        2: avs_readdata_o = {28'b0, boot_fetch_seen_i, pll_locked_i, release_cluster_q,
                             cluster_hold_reset_o};
        3: avs_readdata_o = {{(32-AvalonAddrWidth){1'b0}}, ClusterBaseWord} << 2;
        default: avs_readdata_o = 32'h0000_0000;
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      release_cluster_q <= 1'b0;
    end else if (avs_write_i && !cluster_selected && avs_address_i == 1 &&
                 avs_byteenable_i[0]) begin
      release_cluster_q <= avs_writedata_i[0];
    end
  end
endmodule
