module axi_boot_ram #(
  parameter logic [31:0] BaseAddr = 32'h0000_1000,
  parameter int unsigned RamBytes = 4096,
  parameter int unsigned IdWidth = 3
) (
  input  logic               clk_i,
  input  logic               rst_ni,
  input  logic               host_write_i,
  input  logic [9:0]         host_word_addr_i,
  input  logic [31:0]        host_wdata_i,
  input  logic [3:0]         host_be_i,
  input  logic               ar_valid_i,
  output logic               ar_ready_o,
  input  logic [31:0]        ar_addr_i,
  input  logic [7:0]         ar_len_i,
  input  logic [2:0]         ar_size_i,
  input  logic [1:0]         ar_burst_i,
  input  logic [IdWidth-1:0] ar_id_i,
  output logic               r_valid_o,
  input  logic               r_ready_i,
  output logic [63:0]        r_data_o,
  output logic [1:0]         r_resp_o,
  output logic               r_last_o,
  output logic [IdWidth-1:0] r_id_o,
  output logic               fetch_seen_o
);
  localparam int unsigned NumBeats = RamBytes / 8;
  localparam int unsigned BeatAddrWidth = $clog2(NumBeats);

  logic active_q, fetch_seen_q;
  logic [31:0] addr_q;
  logic [7:0] beats_left_q;
  logic [2:0] size_q;
  logic [1:0] burst_q;
  logic [IdWidth-1:0] id_q;
  logic [63:0] mem_rdata;
  logic [BeatAddrWidth-1:0] mem_read_addr;
  logic address_valid;
  logic [31:0] next_addr;

  assign ar_ready_o = ~active_q;
  assign r_valid_o = active_q;
  assign r_last_o = active_q && beats_left_q == 0;
  assign r_id_o = id_q;
  assign address_valid = addr_q >= BaseAddr && addr_q + 7 < BaseAddr + RamBytes;
  assign r_resp_o = address_valid ? 2'b00 : 2'b11;
  assign r_data_o = address_valid ? mem_rdata : 64'b0;
  assign fetch_seen_o = fetch_seen_q;
  assign next_addr = burst_q == 2'b01 ? addr_q + (32'b1 << size_q) : addr_q;
  always_comb begin
    mem_read_addr = addr_q[BeatAddrWidth+2:3];
    if (ar_valid_i && ar_ready_o && ar_addr_i >= BaseAddr && ar_addr_i < BaseAddr + RamBytes)
      mem_read_addr = ar_addr_i[BeatAddrWidth+2:3];
    else if (r_valid_o && r_ready_i && beats_left_q != 0 &&
             next_addr >= BaseAddr && next_addr < BaseAddr + RamBytes)
      mem_read_addr = next_addr[BeatAddrWidth+2:3];
  end

`ifdef VERILATOR
  logic [63:0] mem [0:NumBeats-1];
  integer byte_idx;
  always_ff @(posedge clk_i) begin
    if (host_write_i) begin
      for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
        if (host_be_i[byte_idx])
          mem[host_word_addr_i[9:1]][host_word_addr_i[0] * 32 + byte_idx * 8 +: 8]
            <= host_wdata_i[byte_idx * 8 +: 8];
      end
    end
  end
  assign mem_rdata = mem[mem_read_addr];
`else
  altsyncram #(
    .operation_mode("DUAL_PORT"), .intended_device_family("Cyclone V"),
    .ram_block_type("M10K"), .numwords_a(1024), .widthad_a(10), .width_a(32),
    .width_byteena_a(4), .numwords_b(512), .widthad_b(9), .width_b(64),
    .width_byteena_b(1), .byte_size(8), .outdata_reg_a("UNREGISTERED"),
    .outdata_reg_b("UNREGISTERED"), .clock_enable_input_a("BYPASS"),
    .clock_enable_input_b("BYPASS"), .clock_enable_output_b("BYPASS"),
    .read_during_write_mode_mixed_ports("DONT_CARE"),
    .power_up_uninitialized("TRUE"), .lpm_type("altsyncram")
  ) i_boot_m10k (
    .clock0(clk_i), .clock1(clk_i), .address_a(host_word_addr_i),
    .data_a(host_wdata_i), .byteena_a(host_be_i), .wren_a(host_write_i),
    .rden_a(1'b0), .q_a(), .address_b(mem_read_addr), .data_b(64'b0),
    .byteena_b(1'b1), .wren_b(1'b0), .rden_b(1'b1), .q_b(mem_rdata),
    .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
    .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .eccstatus()
  );
`endif

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      active_q <= 1'b0;
      addr_q <= '0;
      beats_left_q <= '0;
      size_q <= '0;
      burst_q <= '0;
      id_q <= '0;
      fetch_seen_q <= 1'b0;
    end else if (ar_valid_i && ar_ready_o) begin
      active_q <= 1'b1;
      addr_q <= ar_addr_i;
      beats_left_q <= ar_len_i;
      size_q <= ar_size_i;
      burst_q <= ar_burst_i;
      id_q <= ar_id_i;
      if (ar_addr_i >= BaseAddr && ar_addr_i + 7 < BaseAddr + RamBytes) begin
        fetch_seen_q <= 1'b1;
      end
    end else if (r_valid_o && r_ready_i) begin
      if (beats_left_q == 0) begin
        active_q <= 1'b0;
      end else begin
        beats_left_q <= beats_left_q - 1'b1;
        addr_q <= next_addr;
      end
    end
  end
endmodule
