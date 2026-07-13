module axi_boot_ram_tb;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic host_write, ar_valid, ar_ready, r_valid, r_ready, r_last, fetch_seen;
  logic [9:0] host_word_addr;
  logic [31:0] host_wdata, ar_addr;
  logic [3:0] host_be;
  logic [7:0] ar_len;
  logic [2:0] ar_size;
  logic [1:0] ar_burst, r_resp;
  logic [2:0] ar_id, r_id;
  logic [63:0] r_data;

  axi_boot_ram dut (.*,
    .clk_i(clk), .rst_ni(rst_n), .host_write_i(host_write),
    .host_word_addr_i(host_word_addr), .host_wdata_i(host_wdata), .host_be_i(host_be),
    .ar_valid_i(ar_valid), .ar_ready_o(ar_ready), .ar_addr_i(ar_addr),
    .ar_len_i(ar_len), .ar_size_i(ar_size), .ar_burst_i(ar_burst), .ar_id_i(ar_id),
    .r_valid_o(r_valid), .r_ready_i(r_ready), .r_data_o(r_data), .r_resp_o(r_resp),
    .r_last_o(r_last), .r_id_o(r_id), .fetch_seen_o(fetch_seen));

  task automatic tick; @(posedge clk); #1; endtask
  task automatic write_word(input logic [9:0] addr, input logic [31:0] data);
    host_word_addr = addr; host_wdata = data; host_write = 1; tick(); host_write = 0;
  endtask

  initial begin
    host_write = 0; host_word_addr = 0; host_wdata = 0; host_be = 4'hf;
    ar_valid = 0; ar_addr = 0; ar_len = 0; ar_size = 3; ar_burst = 1; ar_id = 0;
    r_ready = 0;
    repeat (2) tick(); rst_n = 1; tick();
    write_word(0, 32'h0000_22b7); write_word(1, 32'h5a50_0313);
    write_word(2, 32'h0062_a023); write_word(3, 32'h0000_006f);
    host_be = 4'b0011; write_word(1, 32'hffff_0313); host_be = 4'hf;

    ar_addr = 32'h1000; ar_len = 1; ar_id = 3'h5; ar_valid = 1; tick(); ar_valid = 0;
    assert (r_valid && !r_last && r_resp == 0 && r_id == 5);
    assert (r_data == 64'h5a500313000022b7 && fetch_seen);
    repeat (2) tick();
    assert (r_data == 64'h5a500313000022b7);
    r_ready = 1; tick(); r_ready = 0;
    assert (r_valid && r_last && r_data == 64'h0000006f0062a023);
    r_ready = 1; tick(); r_ready = 0; assert (!r_valid);

    ar_addr = 32'h2000; ar_len = 0; ar_valid = 1; tick(); ar_valid = 0;
    assert (r_valid && r_resp == 3 && r_data == 0);
    $display("H2_AXI_BOOT_RAM_PASS");
    $finish;
  end
endmodule
