module de1_s19_genus_snitch_data_ram (
    input  logic       CLOCK_50,
    input  logic [0:0] KEY,
    output logic [9:0] LEDR
);
  `include "rom_words.svh"

  localparam logic [32:0] MMIO_LED_ADDR = 33'h0_4000_0000;
  localparam logic [32:0] RAM_BASE_ADDR = 33'h0_0000_1000;
  localparam int unsigned RAM_WORDS = 16;

  logic rst_i;
  logic [31:0] inst_data;
  logic [32:0] inst_addr;
  logic inst_valid;
  logic data_q_valid;
  logic data_q_ready;
  logic data_q_write;
  logic [32:0] data_q_addr;
  logic [31:0] data_q_data;
  logic [3:0] data_q_strb;
  logic data_p_valid;
  logic data_p_ready;
  logic [31:0] data_p_data;
  logic data_p_error;
  logic barrier;

  logic [8:0] led_data_q;
  logic [31:0] ram_q [RAM_WORDS];
  logic data_rsp_valid_q;
  logic [31:0] data_rsp_data_q;
  logic data_rsp_error_q;

  logic data_q_fire;
  logic data_p_fire;
  logic mmio_access;
  logic ram_access;
  logic [3:0] ram_word_index;

  assign rst_i = ~KEY[0];
  assign inst_data = s19_rom_word({2'b0, inst_addr[31:2]});

  assign data_q_ready = ~data_rsp_valid_q;
  assign data_p_valid = data_rsp_valid_q;
  assign data_p_data = data_rsp_data_q;
  assign data_p_error = data_rsp_error_q;

  assign data_q_fire = data_q_valid && data_q_ready;
  assign data_p_fire = data_p_valid && data_p_ready;
  assign mmio_access = data_q_addr == MMIO_LED_ADDR;
  assign ram_access = data_q_addr[32:6] == RAM_BASE_ADDR[32:6];
  assign ram_word_index = data_q_addr[5:2];

  always_ff @(posedge CLOCK_50 or posedge rst_i) begin
    if (rst_i) begin
      led_data_q <= '0;
      data_rsp_valid_q <= 1'b0;
      data_rsp_data_q <= '0;
      data_rsp_error_q <= 1'b0;
      for (int unsigned i = 0; i < RAM_WORDS; i++) begin
        ram_q[i] <= '0;
      end
    end else begin
      if (data_p_fire) begin
        data_rsp_valid_q <= 1'b0;
      end

      if (data_q_fire) begin
        data_rsp_valid_q <= 1'b1;
        data_rsp_error_q <= 1'b0;

        if (mmio_access && !data_q_write) begin
          data_rsp_data_q <= {23'b0, led_data_q};
        end else if (ram_access && !data_q_write) begin
          data_rsp_data_q <= ram_q[ram_word_index];
        end else begin
          data_rsp_data_q <= '0;
        end

        if (data_q_write && mmio_access) begin
          if (data_q_strb[0]) begin
            led_data_q[7:0] <= data_q_data[7:0];
          end
          if (data_q_strb[1]) begin
            led_data_q[8] <= data_q_data[8];
          end
        end

        if (data_q_write && ram_access) begin
          if (data_q_strb[0]) begin
            ram_q[ram_word_index][7:0] <= data_q_data[7:0];
          end
          if (data_q_strb[1]) begin
            ram_q[ram_word_index][15:8] <= data_q_data[15:8];
          end
          if (data_q_strb[2]) begin
            ram_q[ram_word_index][23:16] <= data_q_data[23:16];
          end
          if (data_q_strb[3]) begin
            ram_q[ram_word_index][31:24] <= data_q_data[31:24];
          end
        end
      end
    end
  end

  snitch_genus_mem_probe i_snitch_genus_mem_probe (
      .clk_i          (CLOCK_50),
      .rst_i,
      .hart_id_i      (32'd0),
      .inst_data_i    (inst_data),
      .inst_ready_i   (1'b1),
      .inst_addr_o    (inst_addr),
      .inst_valid_o   (inst_valid),
      .data_q_valid_o (data_q_valid),
      .data_q_ready_i (data_q_ready),
      .data_q_write_o (data_q_write),
      .data_q_addr_o  (data_q_addr),
      .data_q_data_o  (data_q_data),
      .data_q_strb_o  (data_q_strb),
      .data_p_valid_i (data_p_valid),
      .data_p_ready_o (data_p_ready),
      .data_p_data_i  (data_p_data),
      .data_p_error_i (data_p_error),
      .barrier_o      (barrier)
  );

  assign LEDR[8:0] = led_data_q;
  assign LEDR[9] = ~rst_i;
endmodule
