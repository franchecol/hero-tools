module axi_shared_data_ram #(
  parameter logic [31:0] BaseAddr = 32'h0000_4000,
  parameter logic [31:0] ResultAddr = 32'h0000_2000,
  parameter logic [31:0] DoorbellAddr = 32'h0000_3000,
  parameter int unsigned RamBytes = 4096,
  parameter int unsigned IdWidth = 4
) (
  input  logic               clk_i,
  input  logic               rst_ni,
  input  logic               host_write_i,
  input  logic [9:0]         host_word_addr_i,
  input  logic [31:0]        host_wdata_i,
  input  logic [3:0]         host_be_i,
  output logic [31:0]        host_rdata_o,
  input  logic               job_active_i,
  input  logic               result_ack_i,

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

  input  logic               aw_valid_i,
  output logic               aw_ready_o,
  input  logic [31:0]        aw_addr_i,
  input  logic [IdWidth-1:0] aw_id_i,
  input  logic               w_valid_i,
  output logic               w_ready_o,
  input  logic [63:0]        w_data_i,
  input  logic [7:0]         w_strb_i,
  input  logic               w_last_i,
  output logic               b_valid_o,
  input  logic               b_ready_i,
  output logic [1:0]         b_resp_o,
  output logic [IdWidth-1:0] b_id_o,

  output logic               result_valid_o,
  output logic [31:0]        result_o
);
  localparam int unsigned NumBeats = RamBytes / 8;
  localparam int unsigned BeatAddrWidth = $clog2(NumBeats);

  logic read_active_q;
  logic [31:0] read_addr_q;
  logic [7:0] read_beats_left_q;
  logic [2:0] read_size_q;
  logic [1:0] read_burst_q;
  logic [IdWidth-1:0] read_id_q;

  logic aw_pending_q, w_pending_q, b_valid_q;
  logic [31:0] aw_addr_q;
  logic [IdWidth-1:0] aw_id_q, b_id_q;
  logic [63:0] w_data_q;
  logic [7:0] w_strb_q;
  logic w_last_q;
  logic [1:0] b_resp_q;
  logic result_valid_q;
  logic [31:0] result_q;

  logic aw_fire, w_fire, write_commit;
  logic [31:0] complete_addr;
  logic [IdWidth-1:0] complete_id;
  logic [63:0] complete_data;
  logic [7:0] complete_strb;
  logic complete_last;
  logic write_is_data, write_is_result;
  logic [31:0] next_read_addr;
  logic read_address_valid;
  logic read_is_data, read_is_doorbell;
  logic [BeatAddrWidth-1:0] mem_read_addr, mem_write_addr;
  logic [63:0] mem_rdata;

  assign ar_ready_o = ~read_active_q && ~aw_pending_q && ~w_pending_q && ~b_valid_q;
  assign r_valid_o = read_active_q;
  assign r_last_o = read_active_q && read_beats_left_q == 0;
  assign r_id_o = read_id_q;
  assign read_is_data = read_addr_q >= BaseAddr &&
                        read_addr_q + 7 < BaseAddr + RamBytes;
  assign read_is_doorbell = read_addr_q == DoorbellAddr;
  assign read_address_valid = read_is_data || read_is_doorbell;
  assign r_resp_o = read_address_valid ? 2'b00 : 2'b11;
  assign r_data_o = read_is_doorbell ? {63'b0, job_active_i} :
                    read_is_data ? mem_rdata : 64'b0;
  assign next_read_addr = read_burst_q == 2'b01
                        ? read_addr_q + (32'b1 << read_size_q) : read_addr_q;

  assign aw_ready_o = ~read_active_q && ~aw_pending_q && ~b_valid_q;
  assign w_ready_o = ~read_active_q && ~w_pending_q && ~b_valid_q;
  assign aw_fire = aw_valid_i && aw_ready_o;
  assign w_fire = w_valid_i && w_ready_o;
  assign complete_addr = aw_fire ? aw_addr_i : aw_addr_q;
  assign complete_id = aw_fire ? aw_id_i : aw_id_q;
  assign complete_data = w_fire ? w_data_i : w_data_q;
  assign complete_strb = w_fire ? w_strb_i : w_strb_q;
  assign complete_last = w_fire ? w_last_i : w_last_q;
  assign write_commit = ~b_valid_q && (aw_pending_q || aw_fire) &&
                        (w_pending_q || w_fire);
  assign write_is_data = complete_addr >= BaseAddr &&
                         complete_addr < BaseAddr + RamBytes && complete_last;
  assign write_is_result = complete_addr == ResultAddr && complete_last &&
                           (complete_addr[2] ? |complete_strb[7:4]
                                             : |complete_strb[3:0]);
  assign mem_write_addr = complete_addr[BeatAddrWidth+2:3];

  assign b_valid_o = b_valid_q;
  assign b_resp_o = b_resp_q;
  assign b_id_o = b_id_q;
  assign result_valid_o = result_valid_q;
  assign result_o = result_q;

  always_comb begin
    mem_read_addr = read_addr_q[BeatAddrWidth+2:3];
    if (ar_valid_i && ar_ready_o && ar_addr_i >= BaseAddr && ar_addr_i < BaseAddr + RamBytes)
      mem_read_addr = ar_addr_i[BeatAddrWidth+2:3];
    else if (r_valid_o && r_ready_i && read_beats_left_q != 0 &&
             next_read_addr >= BaseAddr && next_read_addr < BaseAddr + RamBytes)
      mem_read_addr = next_read_addr[BeatAddrWidth+2:3];
  end

`ifdef VERILATOR
  logic [63:0] mem [0:NumBeats-1];
  integer byte_idx;
  always_ff @(posedge clk_i) begin
    if (host_write_i) begin
      for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1)
        if (host_be_i[byte_idx])
          mem[host_word_addr_i[9:1]][host_word_addr_i[0] * 32 + byte_idx * 8 +: 8]
            <= host_wdata_i[byte_idx * 8 +: 8];
    end
    if (write_commit && write_is_data) begin
      for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1)
        if (complete_strb[byte_idx])
          mem[mem_write_addr][byte_idx * 8 +: 8] <= complete_data[byte_idx * 8 +: 8];
    end
  end
  assign host_rdata_o = host_word_addr_i[0]
                        ? mem[host_word_addr_i[9:1]][63:32]
                        : mem[host_word_addr_i[9:1]][31:0];
  assign mem_rdata = mem[mem_read_addr];
`else
  altsyncram #(
    .operation_mode("BIDIR_DUAL_PORT"), .intended_device_family("Cyclone V"),
    .ram_block_type("M10K"), .numwords_a(1024), .widthad_a(10), .width_a(32),
    .width_byteena_a(4), .numwords_b(512), .widthad_b(9), .width_b(64),
    .width_byteena_b(8), .byte_size(8), .outdata_reg_a("UNREGISTERED"),
    .outdata_reg_b("UNREGISTERED"), .clock_enable_input_a("BYPASS"),
    .clock_enable_input_b("BYPASS"), .clock_enable_output_a("BYPASS"),
    .clock_enable_output_b("BYPASS"),
    .read_during_write_mode_mixed_ports("DONT_CARE"),
    .power_up_uninitialized("TRUE"), .lpm_type("altsyncram")
  ) i_data_m10k (
    .clock0(clk_i), .clock1(clk_i), .address_a(host_word_addr_i),
    .data_a(host_wdata_i), .byteena_a(host_be_i), .wren_a(host_write_i),
    .rden_a(1'b1), .q_a(host_rdata_o), .address_b(write_commit && write_is_data
      ? mem_write_addr : mem_read_addr), .data_b(complete_data),
    .byteena_b(complete_strb), .wren_b(write_commit && write_is_data),
    .rden_b(1'b1), .q_b(mem_rdata), .aclr0(1'b0), .aclr1(1'b0),
    .addressstall_a(1'b0), .addressstall_b(1'b0), .clocken0(1'b1),
    .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1), .eccstatus()
  );
`endif

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      read_active_q <= 1'b0;
      read_addr_q <= '0;
      read_beats_left_q <= '0;
      read_size_q <= '0;
      read_burst_q <= '0;
      read_id_q <= '0;
      aw_pending_q <= 1'b0;
      w_pending_q <= 1'b0;
      b_valid_q <= 1'b0;
      aw_addr_q <= '0;
      aw_id_q <= '0;
      w_data_q <= '0;
      w_strb_q <= '0;
      w_last_q <= 1'b0;
      b_id_q <= '0;
      b_resp_q <= 2'b00;
      result_valid_q <= 1'b0;
      result_q <= '0;
    end else begin
      if (result_ack_i) result_valid_q <= 1'b0;
      if (ar_valid_i && ar_ready_o) begin
        read_active_q <= 1'b1;
        read_addr_q <= ar_addr_i;
        read_beats_left_q <= ar_len_i;
        read_size_q <= ar_size_i;
        read_burst_q <= ar_burst_i;
        read_id_q <= ar_id_i;
      end else if (r_valid_o && r_ready_i) begin
        if (read_beats_left_q == 0) read_active_q <= 1'b0;
        else begin
          read_beats_left_q <= read_beats_left_q - 1'b1;
          read_addr_q <= next_read_addr;
        end
      end

      if (aw_fire) begin
        aw_pending_q <= 1'b1;
        aw_addr_q <= aw_addr_i;
        aw_id_q <= aw_id_i;
      end
      if (w_fire) begin
        w_pending_q <= 1'b1;
        w_data_q <= w_data_i;
        w_strb_q <= w_strb_i;
        w_last_q <= w_last_i;
      end
      if (write_commit) begin
        aw_pending_q <= 1'b0;
        w_pending_q <= 1'b0;
        b_valid_q <= 1'b1;
        b_id_q <= complete_id;
        b_resp_q <= (write_is_data || write_is_result) ? 2'b00 : 2'b11;
        if (write_is_result) begin
          result_q <= complete_addr[2] ? complete_data[63:32] : complete_data[31:0];
          result_valid_q <= 1'b1;
        end
      end
      if (b_valid_q && b_ready_i) b_valid_q <= 1'b0;
    end
  end
endmodule
