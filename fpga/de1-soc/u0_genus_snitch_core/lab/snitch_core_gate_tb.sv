`timescale 1ns/1ps

module snitch_core_gate_tb;
  logic        clk_i;
  logic        rst_i;
  logic [31:0] hart_id_i;
  logic [31:0] inst_data_i;
  logic        inst_ready_i;
  logic [32:0] inst_addr_o;
  logic        inst_valid_o;
  logic        data_q_valid_o;
  logic        data_q_write_o;
  logic [32:0] data_q_addr_o;
  logic [31:0] data_q_data_o;
  logic [3:0]  data_q_strb_o;
  logic        barrier_o;

  int unsigned valid_fetches;
  logic [32:0] highest_fetch_addr;

  snitch_genus_probe dut (
      .clk_i,
      .rst_i,
      .hart_id_i,
      .inst_data_i,
      .inst_ready_i,
      .inst_addr_o,
      .inst_valid_o,
      .data_q_valid_o,
      .data_q_write_o,
      .data_q_addr_o,
      .data_q_data_o,
      .data_q_strb_o,
      .barrier_o
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_i = 1'b1;
    hart_id_i = 32'd0;
    inst_data_i = 32'h0000_0013;
    inst_ready_i = 1'b1;
    valid_fetches = 0;
    highest_fetch_addr = '0;

    repeat (4) @(posedge clk_i);
    rst_i = 1'b0;

    repeat (16) begin
      @(posedge clk_i);
      #1;
      if (inst_valid_o === 1'b1) begin
        valid_fetches++;
        if (inst_addr_o > highest_fetch_addr) begin
          highest_fetch_addr = inst_addr_o;
        end
      end
    end

    if (valid_fetches < 4) begin
      $fatal(1, "FAIL: only %0d valid fetches", valid_fetches);
    end
    if (highest_fetch_addr < 33'd12) begin
      $fatal(1, "FAIL: highest fetch address is 0x%0h", highest_fetch_addr);
    end

    $display("PASS: fetches=%0d highest_addr=0x%0h",
             valid_fetches, highest_fetch_addr);
    $finish;
  end
endmodule
