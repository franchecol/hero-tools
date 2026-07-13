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
  logic boot_result_valid, irq;
  logic boot_host_write;
  logic [9:0] boot_host_word_addr;
  logic [31:0] boot_host_wdata;
  logic [3:0] boot_host_be;

  safe_host_control dut (
    .clk_i(clk), .rst_i(rst), .pll_locked_i(1'b1), .boot_fetch_seen_i(1'b0),
    .boot_result_valid_i(boot_result_valid), .boot_result_i(32'h0000_05a5),
    .avs_address_i(avs_address), .avs_read_i(avs_read),
    .avs_readdata_o(avs_readdata), .avs_write_i(avs_write),
    .avs_writedata_i(avs_writedata), .avs_byteenable_i(avs_byteenable),
    .avs_waitrequest_o(avs_waitrequest),
    .cluster_hold_reset_o(cluster_hold_reset),
    .cluster_address_o(cluster_address), .cluster_read_o(cluster_read),
    .cluster_readdata_i(cluster_readdata), .cluster_write_o(cluster_write),
    .cluster_writedata_o(cluster_writedata),
    .cluster_byteenable_o(cluster_byteenable),
    .cluster_waitrequest_i(cluster_waitrequest),
    .boot_host_write_o(boot_host_write), .boot_host_word_addr_o(boot_host_word_addr),
    .boot_host_wdata_o(boot_host_wdata), .boot_host_be_o(boot_host_be), .irq_o(irq)
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
    boot_result_valid = 0;

    repeat (2) tick();
    assert (cluster_hold_reset);
    rst = 0; tick();

    avs_read = 1;
    assert (avs_readdata == 32'h4830_0005 && !avs_waitrequest);
    assert (!cluster_read && !cluster_write);
    avs_address = 2; settle();
    assert (avs_readdata == 32'h0000_0005);
    avs_address = 3; settle();
    assert (avs_readdata == 32'h0000_2000);
    avs_address = 7; settle(); assert (avs_readdata == 32'h0000_1000);
    avs_address = 8; settle(); assert (avs_readdata == 32'd4096);
    avs_read = 0;

    avs_address = 16'h0403; avs_writedata = 32'hdead_beef; avs_byteenable = 4'b0101;
    avs_write = 1; settle();
    assert (boot_host_write && boot_host_word_addr == 3 &&
            boot_host_wdata == 32'hdead_beef && boot_host_be == 4'b0101);
    tick(); avs_write = 0;

    avs_address = 1; avs_writedata = 1; avs_byteenable = 4'b0010;
    avs_write = 1; tick(); avs_write = 0;
    assert (cluster_hold_reset);
    avs_byteenable = 4'b0001; avs_write = 1; tick(); avs_write = 0;
    assert (!cluster_hold_reset);

    avs_address = 16'h0403; avs_writedata = 32'hdead_beef; avs_byteenable = 4'b0101;
    avs_write = 1; settle();
    assert (!boot_host_write);
    tick(); avs_write = 0;

    avs_address = 16'h0803; avs_read = 1; cluster_waitrequest = 1; settle();
    assert (cluster_read && cluster_address == 16'h0003);
    assert (avs_waitrequest && avs_readdata == 32'hcafe_f00d);
    avs_read = 0; avs_write = 1; avs_writedata = 32'h1234_5678;
    avs_byteenable = 4'b0101; cluster_waitrequest = 0; settle();
    assert (cluster_write && cluster_writedata == 32'h1234_5678);
    assert (cluster_byteenable == 4'b0101 && !avs_waitrequest);

    avs_read = 0; avs_address = 16'h0404; avs_write = 1; settle();
    assert (!boot_host_write);
    avs_write = 0;

    avs_read = 0; avs_write = 0; avs_byteenable = 4'hf;
    boot_result_valid = 1; tick();
    avs_address = 6; avs_read = 1; settle();
    assert (avs_readdata == 32'h0000_0001 && !irq);
    avs_read = 0; avs_address = 5; avs_writedata = 1; avs_write = 1;
    tick(); avs_write = 0;
    assert (irq);
    avs_address = 6; avs_read = 1; settle();
    assert (avs_readdata == 32'h0000_0007);
    avs_read = 0; avs_writedata = 1; avs_write = 1;
    tick(); avs_write = 0;
    assert (!irq);
    avs_read = 1; settle();
    assert (avs_readdata == 32'h0000_0002);
    boot_result_valid = 0; tick();
    boot_result_valid = 1; tick();
    assert (irq);

    $display("H1_IRQ_CONTROL_PASS");
    $finish;
  end
endmodule
