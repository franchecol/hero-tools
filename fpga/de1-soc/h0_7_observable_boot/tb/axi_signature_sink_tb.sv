module axi_signature_sink_tb;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic aw_valid, aw_ready, w_valid, w_ready, w_last;
  logic [31:0] aw_addr;
  logic [3:0] aw_id, b_id;
  logic [63:0] w_data;
  logic [7:0] w_strb;
  logic b_valid, b_ready, result_valid;
  logic [1:0] b_resp;
  logic [31:0] result;

  axi_signature_sink dut (
    .clk_i(clk), .rst_ni(rst_n), .aw_valid_i(aw_valid),
    .aw_ready_o(aw_ready), .aw_addr_i(aw_addr), .aw_id_i(aw_id),
    .w_valid_i(w_valid), .w_ready_o(w_ready), .w_data_i(w_data),
    .w_strb_i(w_strb), .w_last_i(w_last), .b_valid_o(b_valid),
    .b_ready_i(b_ready), .b_resp_o(b_resp), .b_id_o(b_id),
    .result_valid_o(result_valid), .result_o(result)
  );

  task automatic tick;
    @(posedge clk); #1;
  endtask

  initial begin
    aw_valid = 0; aw_addr = 0; aw_id = 0;
    w_valid = 0; w_data = 0; w_strb = 0; w_last = 1; b_ready = 0;
    repeat (2) tick(); rst_n = 1; tick();

    // Accept AW and W independently, as permitted by AXI.
    aw_addr = 32'h2000; aw_id = 4'h9; aw_valid = 1;
    tick(); aw_valid = 0;
    assert (!b_valid && w_ready);
    w_data = 64'h00000000000005a5; w_strb = 8'h0f; w_valid = 1;
    tick(); w_valid = 0;
    assert (b_valid && b_resp == 0 && b_id == 4'h9);
    assert (result_valid && result == 32'h000005a5);

    // B response and result remain stable under backpressure.
    repeat (2) begin assert (b_valid && result == 32'h5a5); tick(); end
    b_ready = 1; tick(); b_ready = 0;
    assert (!b_valid && result_valid);

    // An unsupported address returns DECERR without changing the signature.
    aw_addr = 32'h3000; aw_id = 4'h2; aw_valid = 1;
    w_data = 64'hdeadbeef; w_strb = 8'h0f; w_valid = 1;
    tick(); aw_valid = 0; w_valid = 0;
    assert (b_valid && b_resp == 2'b11 && b_id == 4'h2);
    assert (result == 32'h5a5);

    $display("H0.7_AXI_SIGNATURE_SINK_PASS");
    $finish;
  end
endmodule
