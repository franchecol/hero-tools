module avalon_to_narrow_axi #(
  parameter logic [31:0] AxiBaseAddr = 32'h1000_0000,
  parameter int unsigned AvalonAddrWidth = 18
) (
  input  logic                       clk_i,
  input  logic                       rst_i,

  input  logic [AvalonAddrWidth-1:0] avs_address_i,
  input  logic                       avs_read_i,
  output logic [31:0]                avs_readdata_o,
  input  logic                       avs_write_i,
  input  logic [31:0]                avs_writedata_i,
  input  logic [3:0]                 avs_byteenable_i,
  output logic                       avs_waitrequest_o,

  output logic                       axi_r_ready_o,
  output logic                       axi_ar_valid_o,
  output logic [31:0]                axi_ar_addr_o,
  output logic [2:0]                 axi_ar_size_o,
  input  logic                       axi_ar_ready_i,
  input  logic                       axi_r_valid_i,
  input  logic [63:0]                axi_r_data_i,
  input  logic [1:0]                 axi_r_resp_i,

  output logic                       axi_b_ready_o,
  output logic                       axi_w_valid_o,
  output logic [63:0]                axi_w_data_o,
  output logic [7:0]                 axi_w_strb_o,
  output logic                       axi_w_last_o,
  output logic                       axi_aw_valid_o,
  output logic [31:0]                axi_aw_addr_o,
  output logic [2:0]                 axi_aw_size_o,
  input  logic                       axi_aw_ready_i,
  input  logic                       axi_w_ready_i,
  input  logic                       axi_b_valid_i,
  input  logic [1:0]                 axi_b_resp_i
);
  typedef enum logic [2:0] {Idle, ReadAddress, ReadData, WriteRequest, WriteResponse, Complete} state_t;

  state_t state_q;
  logic address_half_q;
  logic aw_pending_q;
  logic w_pending_q;
  logic [31:0] read_data_q;
  logic [1:0] response_q;

  assign avs_waitrequest_o = (state_q != Complete);
  assign avs_readdata_o = read_data_q;

  assign axi_ar_valid_o = (state_q == ReadAddress);
  assign axi_r_ready_o = (state_q == ReadData);
  assign axi_aw_valid_o = (state_q == WriteRequest) && aw_pending_q;
  assign axi_w_valid_o = (state_q == WriteRequest) && w_pending_q;
  assign axi_w_last_o = 1'b1;
  assign axi_b_ready_o = (state_q == WriteResponse);
  assign axi_ar_size_o = 3'b010;
  assign axi_aw_size_o = 3'b010;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q <= Idle;
      address_half_q <= 1'b0;
      aw_pending_q <= 1'b0;
      w_pending_q <= 1'b0;
      read_data_q <= '0;
      response_q <= '0;
      axi_ar_addr_o <= '0;
      axi_aw_addr_o <= '0;
      axi_w_data_o <= '0;
      axi_w_strb_o <= '0;
    end else begin
      case (state_q)
        Idle: begin
          if (avs_read_i) begin
            address_half_q <= avs_address_i[0];
            axi_ar_addr_o <= AxiBaseAddr + {{(30-AvalonAddrWidth){1'b0}}, avs_address_i, 2'b00};
            state_q <= ReadAddress;
          end else if (avs_write_i) begin
            address_half_q <= avs_address_i[0];
            axi_aw_addr_o <= AxiBaseAddr + {{(30-AvalonAddrWidth){1'b0}}, avs_address_i, 2'b00};
            if (avs_address_i[0]) begin
              axi_w_data_o <= {avs_writedata_i, 32'b0};
              axi_w_strb_o <= {avs_byteenable_i, 4'b0};
            end else begin
              axi_w_data_o <= {32'b0, avs_writedata_i};
              axi_w_strb_o <= {4'b0, avs_byteenable_i};
            end
            aw_pending_q <= 1'b1;
            w_pending_q <= 1'b1;
            state_q <= WriteRequest;
          end
        end

        ReadAddress: begin
          if (axi_ar_ready_i) state_q <= ReadData;
        end

        ReadData: begin
          if (axi_r_valid_i) begin
            read_data_q <= address_half_q ? axi_r_data_i[63:32] : axi_r_data_i[31:0];
            response_q <= axi_r_resp_i;
            state_q <= Complete;
          end
        end

        WriteRequest: begin
          if (axi_aw_valid_o && axi_aw_ready_i) aw_pending_q <= 1'b0;
          if (axi_w_valid_o && axi_w_ready_i) w_pending_q <= 1'b0;
          if ((!aw_pending_q || axi_aw_ready_i) && (!w_pending_q || axi_w_ready_i)) begin
            state_q <= WriteResponse;
          end
        end

        WriteResponse: begin
          if (axi_b_valid_i) begin
            response_q <= axi_b_resp_i;
            state_q <= Complete;
          end
        end

        Complete: state_q <= Idle;
        default: state_q <= Idle;
      endcase
    end
  end

  // Keep the response for future status reporting; Avalon-MM itself has no
  // response signal in this minimal bridge component.
  logic response_unused;
  assign response_unused = ^response_q;
endmodule
