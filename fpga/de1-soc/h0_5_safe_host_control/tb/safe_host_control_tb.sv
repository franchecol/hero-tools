module safe_host_control_tb;
  logic clk = 0;
  logic rst = 1;
  always #5 clk = ~clk;

  logic [15:0] avs_address, cluster_address;
  logic avs_read, avs_write, avs_waitrequest;
  logic [31:0] avs_readdata, avs_writedata;
  logic [3:0] avs_byteenable;
  logic cluster_hold_reset, cluster_read, cluster_write;
  logic [31:0] cluster_readdata, cluster_writedata;
  logic [3:0] cluster_byteenable;
  logic cluster_waitrequest;

  safe_host_control dut (
    .clk_i(clk), .rst_i(rst), .pll_locked_i(1'b1), .boot_fetch_seen_i(1'b0),
    .boot_result_valid_i(1'b0), .boot_result_i(32'b0),
    .avs_address_i(avs_address), .avs_read_i(avs_read),
    .avs_readdata_o(avs_readdata), .avs_write_i(avs_write),
    .avs_writedata_i(avs_writedata), .avs_byteenable_i(avs_byteenable),
    .avs_waitrequest_o(avs_waitrequest),
    .cluster_hold_reset_o(cluster_hold_reset),
    .cluster_address_o(cluster_address), .cluster_read_o(cluster_read),
    .cluster_readdata_i(cluster_readdata), .cluster_write_o(cluster_write),
    .cluster_writedata_o(cluster_writedata),
    .cluster_byteenable_o(cluster_byteenable),
    .cluster_waitrequest_i(cluster_waitrequest)
  );

  task automatic tick;
    @(posedge clk); #1;
  endtask

  task automatic settle;
    #1;
  endtask

  initial begin
    avs_address = 0; avs_read = 0; avs_write = 0;
    avs_writedata = 0; avs_byteenable = 4'hf;
    cluster_readdata = 32'hcafe_f00d; cluster_waitrequest = 0;

    repeat (2) tick();
    assert (cluster_hold_reset);
    rst = 0; tick();

    avs_read = 1;
    assert (avs_readdata == 32'h4830_0005 && !avs_waitrequest);
    assert (!cluster_read && !cluster_write);
    avs_address = 2; settle();
    assert (avs_readdata == 32'h0000_0005);
    avs_address = 3; settle();
    assert (avs_readdata == 32'h0000_1000);
    avs_read = 0;

    avs_address = 1; avs_writedata = 1; avs_byteenable = 4'b0010;
    avs_write = 1; tick(); avs_write = 0;
    assert (cluster_hold_reset);
    avs_byteenable = 4'b0001; avs_write = 1; tick(); avs_write = 0;
    assert (!cluster_hold_reset);

    avs_address = 16'h0403; avs_read = 1; cluster_waitrequest = 1; settle();
    assert (cluster_read && cluster_address == 16'h0003);
    assert (avs_waitrequest && avs_readdata == 32'hcafe_f00d);
    avs_read = 0; avs_write = 1; avs_writedata = 32'h1234_5678;
    avs_byteenable = 4'b0101; cluster_waitrequest = 0; settle();
    assert (cluster_write && cluster_writedata == 32'h1234_5678);
    assert (cluster_byteenable == 4'b0101 && !avs_waitrequest);

    $display("H0.5_SAFE_CONTROL_PASS");
    $finish;
  end
endmodule
