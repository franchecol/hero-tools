module de1_s18_genus_snitch_rom_mmio (
    input  logic       CLOCK_50,
    input  logic [0:0] KEY,
    output logic [9:0] LEDR
);
  `include "rom_words.svh"

  localparam logic [32:0] MMIO_LED_ADDR = 33'h0_4000_0000;

  logic rst_i;
  logic [31:0] inst_data;
  logic [32:0] inst_addr;
  logic inst_valid;
  logic data_q_valid;
  logic data_q_write;
  logic [32:0] data_q_addr;
  logic [31:0] data_q_data;
  logic [3:0] data_q_strb;
  logic barrier;
  logic [9:0] led_data_q;
  logic mmio_seen_q;

  assign rst_i = ~KEY[0];
  assign inst_data = s18_rom_word({2'b0, inst_addr[31:2]});

  always_ff @(posedge CLOCK_50 or posedge rst_i) begin
    if (rst_i) begin
      led_data_q <= '0;
      mmio_seen_q <= 1'b0;
    end else if (data_q_valid && data_q_write &&
                 data_q_addr == MMIO_LED_ADDR) begin
      if (data_q_strb[0]) begin
        led_data_q[7:0] <= data_q_data[7:0];
      end
      if (data_q_strb[1]) begin
        led_data_q[9:8] <= data_q_data[9:8];
      end
      mmio_seen_q <= 1'b1;
    end
  end

  snitch_genus_probe i_snitch_genus_probe (
      .clk_i          (CLOCK_50),
      .rst_i,
      .hart_id_i      (32'd0),
      .inst_data_i    (inst_data),
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

  assign LEDR[7:0] = led_data_q[7:0];
  assign LEDR[8] = mmio_seen_q;
  assign LEDR[9] = ~rst_i;
endmodule
