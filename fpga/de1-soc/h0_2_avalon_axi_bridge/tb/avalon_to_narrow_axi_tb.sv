module avalon_to_narrow_axi_tb;
  logic clk = 0;
  logic rst = 1;
  always #5 clk = ~clk;

  logic [7:0] avs_address;
  logic avs_read, avs_write;
  logic [31:0] avs_readdata, avs_writedata;
  logic [3:0] avs_byteenable;
  logic avs_waitrequest;
  logic r_ready, ar_valid, ar_ready, r_valid;
  logic [31:0] ar_addr;
  logic [2:0] ar_size;
  logic [63:0] r_data;
  logic [1:0] r_resp;
  logic b_ready, w_valid, w_ready, w_last, aw_valid, aw_ready, b_valid;
  logic [63:0] w_data;
  logic [7:0] w_strb;
  logic [31:0] aw_addr;
  logic [2:0] aw_size;
  logic [1:0] b_resp;

  avalon_to_narrow_axi #(.AvalonAddrWidth(8)) dut (
    .clk_i(clk), .rst_i(rst),
    .avs_address_i(avs_address), .avs_read_i(avs_read),
    .avs_readdata_o(avs_readdata), .avs_write_i(avs_write),
    .avs_writedata_i(avs_writedata), .avs_byteenable_i(avs_byteenable),
    .avs_waitrequest_o(avs_waitrequest),
    .axi_r_ready_o(r_ready), .axi_ar_valid_o(ar_valid),
    .axi_ar_addr_o(ar_addr), .axi_ar_size_o(ar_size),
    .axi_ar_ready_i(ar_ready), .axi_r_valid_i(r_valid),
    .axi_r_data_i(r_data), .axi_r_resp_i(r_resp),
    .axi_b_ready_o(b_ready), .axi_w_valid_o(w_valid),
    .axi_w_data_o(w_data), .axi_w_strb_o(w_strb), .axi_w_last_o(w_last),
    .axi_aw_valid_o(aw_valid), .axi_aw_addr_o(aw_addr),
    .axi_aw_size_o(aw_size), .axi_aw_ready_i(aw_ready),
    .axi_w_ready_i(w_ready), .axi_b_valid_i(b_valid), .axi_b_resp_i(b_resp)
  );

  task automatic tick;
    @(posedge clk); #1;
  endtask

  initial begin
    avs_address = 0; avs_read = 0; avs_write = 0;
    avs_writedata = 0; avs_byteenable = 4'hf;
    ar_ready = 0; r_valid = 0; r_data = 0; r_resp = 0;
    aw_ready = 0; w_ready = 0; b_valid = 0; b_resp = 0;
    repeat (2) tick(); rst = 0; tick();

    avs_address = 8'h03; avs_writedata = 32'h89abcdef; avs_write = 1;
    tick(); avs_write = 0;
    assert (aw_valid && w_valid && aw_addr == 32'h1000000c);
    assert (aw_size == 3'b010 && w_data == 64'h89abcdef00000000 && w_strb == 8'hf0 && w_last);
    aw_ready = 1; tick(); aw_ready = 0;
    assert (w_valid);
    w_ready = 1; tick(); w_ready = 0;
    b_valid = 1; tick(); b_valid = 0;
    assert (!avs_waitrequest); tick();

    avs_address = 8'h02; avs_read = 1; tick(); avs_read = 0;
    assert (ar_valid && ar_addr == 32'h10000008 && ar_size == 3'b010);
    ar_ready = 1; tick(); ar_ready = 0;
    r_data = 64'hfedcba9876543210; r_valid = 1; tick(); r_valid = 0;
    assert (!avs_waitrequest && avs_readdata == 32'h76543210); tick();

    avs_address = 8'h03; avs_read = 1; tick(); avs_read = 0;
    ar_ready = 1; tick(); ar_ready = 0;
    r_data = 64'hfedcba9876543210; r_valid = 1; tick(); r_valid = 0;
    assert (!avs_waitrequest && avs_readdata == 32'hfedcba98);

    $display("H0.2_ADAPTER_PASS");
    $finish;
  end
endmodule
