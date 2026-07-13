module safe_host_control #(
  parameter int unsigned AvalonAddrWidth = 16,
  parameter logic [31:0] BlockId = 32'h4830_0005,
  parameter logic [AvalonAddrWidth-1:0] BootBaseWord = 16'h0400,
  parameter logic [AvalonAddrWidth-1:0] DataBaseWord = 16'h0800,
  parameter logic [AvalonAddrWidth-1:0] ClusterBaseWord = 16'h0c00
) (
  input  logic                       clk_i,
  input  logic                       rst_i,
  input  logic                       pll_locked_i,
  input  logic                       boot_fetch_seen_i,
  input  logic                       boot_result_valid_i,
  input  logic [31:0]                boot_result_i,

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
  input  logic                       cluster_waitrequest_i,
  output logic                       boot_host_write_o,
  output logic [9:0]                 boot_host_word_addr_o,
  output logic [31:0]                boot_host_wdata_o,
  output logic [3:0]                 boot_host_be_o,
  output logic                       data_host_write_o,
  output logic [9:0]                 data_host_word_addr_o,
  output logic [31:0]                data_host_wdata_o,
  output logic [3:0]                 data_host_be_o,
  input  logic [31:0]                data_host_rdata_i,
  output logic                       job_active_o,
  output logic                       result_ack_o,
  output logic                       irq_o
);
  logic cluster_selected, boot_selected, data_selected;
  logic release_cluster_q;
  logic irq_enable_q, irq_pending_q, result_seen_q;
  logic data_read_pending_q;
  logic job_active_q, resident_mode_q, data_host_access;

  assign cluster_selected = avs_address_i >= ClusterBaseWord;
  assign data_selected = avs_address_i >= DataBaseWord && avs_address_i < ClusterBaseWord;
  assign boot_selected = avs_address_i >= BootBaseWord && avs_address_i < DataBaseWord;
  assign cluster_address_o = avs_address_i - ClusterBaseWord;
  assign cluster_read_o = avs_read_i && cluster_selected;
  assign cluster_write_o = avs_write_i && cluster_selected;
  assign cluster_writedata_o = avs_writedata_i;
  assign cluster_byteenable_o = avs_byteenable_i;
  assign cluster_hold_reset_o = ~release_cluster_q;
  assign irq_o = irq_enable_q && irq_pending_q;
  assign job_active_o = job_active_q;
  assign result_ack_o = avs_write_i && !cluster_selected && !data_selected &&
                        !boot_selected && avs_address_i == 11 &&
                        avs_byteenable_i[0] && avs_writedata_i[0];
  assign data_host_access = cluster_hold_reset_o ||
                            (resident_mode_q && !job_active_q);
  assign boot_host_write_o = avs_write_i && boot_selected && cluster_hold_reset_o;
  assign boot_host_word_addr_o = avs_address_i[9:0];
  assign boot_host_wdata_o = avs_writedata_i;
  assign boot_host_be_o = avs_byteenable_i;
  assign data_host_write_o = avs_write_i && data_selected && data_host_access;
  assign data_host_word_addr_o = avs_address_i[9:0];
  assign data_host_wdata_o = avs_writedata_i;
  assign data_host_be_o = avs_byteenable_i;

  always_comb begin
    avs_readdata_o = 32'h0000_0000;
    avs_waitrequest_o = 1'b0;
    if (cluster_selected) begin
      avs_readdata_o = cluster_readdata_i;
      avs_waitrequest_o = cluster_waitrequest_i;
    end else if (data_selected) begin
      avs_readdata_o = data_host_access ? data_host_rdata_i : 32'h0000_0000;
      avs_waitrequest_o = avs_read_i && !data_read_pending_q;
    end else if (boot_selected) begin
      avs_readdata_o = 32'h0000_0000;
    end else begin
      case (avs_address_i)
        0: avs_readdata_o = BlockId;
        1: avs_readdata_o = {31'b0, release_cluster_q};
        2: avs_readdata_o = {27'b0, boot_result_valid_i, boot_fetch_seen_i,
                             pll_locked_i, release_cluster_q,
                             cluster_hold_reset_o};
        3: avs_readdata_o = {{(32-AvalonAddrWidth){1'b0}}, ClusterBaseWord} << 2;
        4: avs_readdata_o = boot_result_i;
        5: avs_readdata_o = {31'b0, irq_enable_q};
        6: avs_readdata_o = {29'b0, irq_o, irq_enable_q, irq_pending_q};
        7: avs_readdata_o = {{(32-AvalonAddrWidth){1'b0}}, BootBaseWord} << 2;
        8: avs_readdata_o = 32'd4096;
        9: avs_readdata_o = {{(32-AvalonAddrWidth){1'b0}}, DataBaseWord} << 2;
        10: avs_readdata_o = 32'd4096;
        11: avs_readdata_o = {29'b0, data_host_access, resident_mode_q,
                              job_active_q};
        default: avs_readdata_o = 32'h0000_0000;
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      release_cluster_q <= 1'b0;
      irq_enable_q <= 1'b0;
      irq_pending_q <= 1'b0;
      result_seen_q <= 1'b0;
      data_read_pending_q <= 1'b0;
      job_active_q <= 1'b0;
      resident_mode_q <= 1'b0;
    end else begin
      if (!avs_read_i || !data_selected) data_read_pending_q <= 1'b0;
      else data_read_pending_q <= ~data_read_pending_q;

      if (!boot_result_valid_i) result_seen_q <= 1'b0;
      if (boot_result_valid_i && !result_seen_q) begin
        result_seen_q <= 1'b1;
        irq_pending_q <= 1'b1;
        job_active_q <= 1'b0;
      end

      if (avs_write_i && !cluster_selected && !data_selected && !boot_selected &&
          avs_byteenable_i[0]) begin
        case (avs_address_i)
          1: release_cluster_q <= avs_writedata_i[0];
          5: irq_enable_q <= avs_writedata_i[0];
          6: if (avs_writedata_i[0]) irq_pending_q <= 1'b0;
          11: if (avs_writedata_i[0] && release_cluster_q && !job_active_q) begin
            resident_mode_q <= 1'b1;
            job_active_q <= 1'b1;
          end
          default: begin end
        endcase
      end
    end
  end
endmodule
