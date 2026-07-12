module axi_boot_rom #(
  parameter logic [31:0] BaseAddr = 32'h0000_1000,
  parameter int unsigned RomBytes = 256,
  parameter int unsigned IdWidth = 4
) (
  input  logic               clk_i,
  input  logic               rst_ni,

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
  localparam logic [1:0] RespOkay = 2'b00;
  localparam logic [1:0] RespDecerr = 2'b11;

  logic active_q;
  logic [31:0] addr_q;
  logic [7:0] beats_left_q;
  logic [2:0] size_q;
  logic [1:0] burst_q;
  logic [IdWidth-1:0] id_q;
  logic fetch_seen_q;
  logic address_valid;

  function automatic logic [31:0] rom_word(input logic [31:0] byte_addr);
    logic [31:0] offset;
    begin
      offset = byte_addr - BaseAddr;
      case (offset[7:2])
        // `jal x0, 0`: remain safely in the external boot ROM.
        default: rom_word = 32'h0000_006f;
      endcase
    end
  endfunction

  assign ar_ready_o = ~active_q;
  assign r_valid_o = active_q;
  assign r_last_o = active_q && beats_left_q == 0;
  assign r_id_o = id_q;
  assign address_valid = addr_q >= BaseAddr && addr_q + 7 < BaseAddr + RomBytes;
  assign r_resp_o = address_valid ? RespOkay : RespDecerr;
  assign r_data_o = address_valid
                    ? {rom_word({addr_q[31:3], 3'b100}),
                       rom_word({addr_q[31:3], 3'b000})}
                    : 64'b0;
  assign fetch_seen_o = fetch_seen_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      active_q <= 1'b0;
      addr_q <= '0;
      beats_left_q <= '0;
      size_q <= '0;
      burst_q <= '0;
      id_q <= '0;
      fetch_seen_q <= 1'b0;
    end else begin
      if (ar_valid_i && ar_ready_o) begin
        active_q <= 1'b1;
        addr_q <= ar_addr_i;
        beats_left_q <= ar_len_i;
        size_q <= ar_size_i;
        burst_q <= ar_burst_i;
        id_q <= ar_id_i;
        if (ar_addr_i >= BaseAddr && ar_addr_i < BaseAddr + RomBytes)
          fetch_seen_q <= 1'b1;
      end else if (r_valid_o && r_ready_i) begin
        if (beats_left_q == 0) begin
          active_q <= 1'b0;
        end else begin
          beats_left_q <= beats_left_q - 1'b1;
          if (burst_q == 2'b01) addr_q <= addr_q + (32'b1 << size_q);
        end
      end
    end
  end
endmodule
