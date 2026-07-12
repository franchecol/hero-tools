module axi_signature_sink #(
  parameter logic [31:0] ResultAddr = 32'h0000_2000,
  parameter int unsigned IdWidth = 4
) (
  input  logic               clk_i,
  input  logic               rst_ni,

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
  logic aw_pending_q, w_pending_q, b_valid_q;
  logic [31:0] aw_addr_q;
  logic [IdWidth-1:0] aw_id_q, b_id_q;
  logic [63:0] w_data_q;
  logic [7:0] w_strb_q;
  logic w_last_q;
  logic [1:0] b_resp_q;
  logic result_valid_q;
  logic [31:0] result_q;

  logic aw_fire, w_fire;
  logic [31:0] complete_addr;
  logic [IdWidth-1:0] complete_id;
  logic [63:0] complete_data;
  logic [7:0] complete_strb;
  logic complete_last;

  assign aw_ready_o = ~aw_pending_q && ~b_valid_q;
  assign w_ready_o = ~w_pending_q && ~b_valid_q;
  assign aw_fire = aw_valid_i && aw_ready_o;
  assign w_fire = w_valid_i && w_ready_o;
  assign complete_addr = aw_fire ? aw_addr_i : aw_addr_q;
  assign complete_id = aw_fire ? aw_id_i : aw_id_q;
  assign complete_data = w_fire ? w_data_i : w_data_q;
  assign complete_strb = w_fire ? w_strb_i : w_strb_q;
  assign complete_last = w_fire ? w_last_i : w_last_q;

  assign b_valid_o = b_valid_q;
  assign b_resp_o = b_resp_q;
  assign b_id_o = b_id_q;
  assign result_valid_o = result_valid_q;
  assign result_o = result_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
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

      if (!b_valid_q && (aw_pending_q || aw_fire) && (w_pending_q || w_fire)) begin
        aw_pending_q <= 1'b0;
        w_pending_q <= 1'b0;
        b_valid_q <= 1'b1;
        b_id_q <= complete_id;
        if (complete_addr == ResultAddr && complete_last &&
            (complete_addr[2] ? |complete_strb[7:4] : |complete_strb[3:0])) begin
          b_resp_q <= 2'b00;
          result_q <= complete_addr[2] ? complete_data[63:32] : complete_data[31:0];
          result_valid_q <= 1'b1;
        end else begin
          b_resp_q <= 2'b11;
        end
      end

      if (b_valid_q && b_ready_i) b_valid_q <= 1'b0;
    end
  end
endmodule
