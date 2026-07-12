module axi_boot_rom_tb;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic ar_valid, ar_ready, r_valid, r_ready, r_last, fetch_seen;
  logic [31:0] ar_addr;
  logic [7:0] ar_len;
  logic [2:0] ar_size;
  logic [1:0] ar_burst, r_resp;
  logic [3:0] ar_id, r_id;
  logic [63:0] r_data;

  axi_boot_rom dut (.*,
    .clk_i(clk), .rst_ni(rst_n),
    .ar_valid_i(ar_valid), .ar_ready_o(ar_ready),
    .ar_addr_i(ar_addr), .ar_len_i(ar_len), .ar_size_i(ar_size),
    .ar_burst_i(ar_burst), .ar_id_i(ar_id),
    .r_valid_o(r_valid), .r_ready_i(r_ready), .r_data_o(r_data),
    .r_resp_o(r_resp), .r_last_o(r_last), .r_id_o(r_id),
    .fetch_seen_o(fetch_seen)
  );

  task automatic tick;
    @(posedge clk); #1;
  endtask

  initial begin
    ar_valid = 0; ar_addr = 0; ar_len = 0; ar_size = 3; ar_burst = 2'b01;
    ar_id = 0; r_ready = 0;
    repeat (2) tick(); rst_n = 1; tick();

    ar_addr = 32'h1000; ar_len = 1; ar_id = 4'ha; ar_valid = 1;
    tick(); ar_valid = 0;
    assert (r_valid && !r_last && r_id == 4'ha && r_resp == 0);
    assert (r_data == 64'h5a500313000022b7 && fetch_seen);

    // Backpressure must preserve the first response exactly.
    repeat (2) begin
      assert (r_valid && !r_last && r_data == 64'h5a500313000022b7);
      tick();
    end
    r_ready = 1; tick(); r_ready = 0;
    assert (r_valid && r_last && r_id == 4'ha && r_resp == 0);
    assert (r_data == 64'h0000006f0062a023);
    r_ready = 1; tick(); r_ready = 0;
    assert (!r_valid && ar_ready);

    ar_addr = 32'h2000; ar_len = 0; ar_id = 4'h3; ar_valid = 1;
    tick(); ar_valid = 0;
    assert (r_valid && r_last && r_id == 4'h3 && r_resp == 2'b11);
    assert (r_data == 0);
    r_ready = 1; tick();

    $display("H0.6_AXI_BOOT_ROM_PASS");
    $finish;
  end
endmodule
