module de1_s17_genus_snitch_core (
    input  logic       CLOCK_50,
    input  logic [0:0] KEY,
    input  logic [9:0] SW,
    output logic [9:0] LEDR
);
  logic rst_i;
  logic [31:0] instruction_stimulus;
  logic [32:0] inst_addr;
  logic inst_valid;
  logic data_q_valid;
  logic data_q_write;
  logic [32:0] data_q_addr;
  logic [31:0] data_q_data;
  logic [3:0] data_q_strb;
  logic barrier;

  assign rst_i = ~KEY[0];

  // Keep all instruction bits dynamic so Quartus cannot reduce the imported
  // core to one constant software path during this compatibility experiment.
  always_ff @(posedge CLOCK_50 or posedge rst_i) begin
    if (rst_i) begin
      instruction_stimulus <= 32'h0000_0013;
    end else begin
      instruction_stimulus <= {
          instruction_stimulus[30:0],
          instruction_stimulus[31] ^ instruction_stimulus[21] ^
              instruction_stimulus[1] ^ instruction_stimulus[0]
      };
      instruction_stimulus[9:0] <= instruction_stimulus[9:0] ^ SW;
    end
  end

  snitch_genus_probe i_snitch_genus_probe (
      .clk_i          (CLOCK_50),
      .rst_i,
      .hart_id_i      (32'd0),
      .inst_data_i    (instruction_stimulus),
      .inst_ready_i   (1'b1),
      .inst_addr_o    (inst_addr),
      .inst_valid_o   (inst_valid),
      .data_q_valid_o (data_q_valid),
      .data_q_write_o (data_q_write),
      .data_q_addr_o  (data_q_addr),
      .data_q_data_o  (data_q_data),
      .data_q_strb_o  (data_q_strb),
      .barrier_o      (barrier)
  );

  assign LEDR[5:0] = inst_addr[7:2];
  assign LEDR[6] = inst_valid;
  assign LEDR[7] = data_q_valid;
  assign LEDR[8] = data_q_write;
  assign LEDR[9] = ~rst_i;
endmodule
