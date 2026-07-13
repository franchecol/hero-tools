module axi_shared_data_ram_tb;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic host_write;
  logic [9:0] host_word_addr;
  logic [31:0] host_wdata, host_rdata;
  logic [3:0] host_be;
  logic ar_valid, ar_ready, r_valid, r_ready, r_last;
  logic [31:0] ar_addr;
  logic [7:0] ar_len;
  logic [2:0] ar_size;
  logic [1:0] ar_burst, r_resp;
  logic [3:0] ar_id, r_id;
  logic [63:0] r_data;
  logic aw_valid, aw_ready, w_valid, w_ready, w_last;
  logic [31:0] aw_addr;
  logic [3:0] aw_id, b_id;
  logic [63:0] w_data;
  logic [7:0] w_strb;
  logic b_valid, b_ready;
  logic [1:0] b_resp;
  logic result_valid;
  logic job_active, result_ack;
  logic [31:0] result;

  axi_shared_data_ram dut (
    .clk_i(clk), .rst_ni(rst_n), .host_write_i(host_write),
    .host_word_addr_i(host_word_addr), .host_wdata_i(host_wdata),
    .host_be_i(host_be), .host_rdata_o(host_rdata),
    .job_active_i(job_active), .result_ack_i(result_ack),
    .ar_valid_i(ar_valid), .ar_ready_o(ar_ready), .ar_addr_i(ar_addr),
    .ar_len_i(ar_len), .ar_size_i(ar_size), .ar_burst_i(ar_burst),
    .ar_id_i(ar_id), .r_valid_o(r_valid), .r_ready_i(r_ready),
    .r_data_o(r_data), .r_resp_o(r_resp), .r_last_o(r_last), .r_id_o(r_id),
    .aw_valid_i(aw_valid), .aw_ready_o(aw_ready), .aw_addr_i(aw_addr),
    .aw_id_i(aw_id), .w_valid_i(w_valid), .w_ready_o(w_ready),
    .w_data_i(w_data), .w_strb_i(w_strb), .w_last_i(w_last),
    .b_valid_o(b_valid), .b_ready_i(b_ready), .b_resp_o(b_resp), .b_id_o(b_id),
    .result_valid_o(result_valid), .result_o(result)
  );

  task automatic tick; @(posedge clk); #1; endtask
  task automatic host_write_word(input logic [9:0] addr, input logic [31:0] data);
    host_word_addr = addr; host_wdata = data; host_write = 1; tick(); host_write = 0;
  endtask
  task automatic axi_write(input logic [31:0] addr, input logic [63:0] data,
                           input logic [7:0] strb, input logic [3:0] id,
                           input logic [1:0] expected_resp);
    aw_addr = addr; aw_id = id; w_data = data; w_strb = strb;
    aw_valid = 1; w_valid = 1; tick(); aw_valid = 0; w_valid = 0;
    assert (b_valid && b_resp == expected_resp && b_id == id);
    b_ready = 1; tick(); b_ready = 0; assert (!b_valid);
  endtask

  initial begin
    host_write = 0; host_word_addr = 0; host_wdata = 0; host_be = 4'hf;
    ar_valid = 0; ar_addr = 0; ar_len = 0; ar_size = 3; ar_burst = 1; ar_id = 0;
    r_ready = 0; aw_valid = 0; aw_addr = 0; aw_id = 0;
    w_valid = 0; w_data = 0; w_strb = 0; w_last = 1; b_ready = 0;
    job_active = 0; result_ack = 0;
    repeat (2) tick(); rst_n = 1; tick();

    host_write_word(0, 32'h1111_2222);
    host_write_word(1, 32'h3333_4444);
    host_be = 4'b0011; host_write_word(0, 32'haaaa_bbbb); host_be = 4'hf;
    host_word_addr = 0; #1; assert (host_rdata == 32'h1111_bbbb);
    host_word_addr = 1; #1; assert (host_rdata == 32'h3333_4444);

    ar_addr = 32'h4000; ar_len = 0; ar_id = 4'ha; ar_valid = 1;
    tick(); ar_valid = 0;
    assert (r_valid && r_last && r_resp == 0 && r_id == 4'ha);
    assert (r_data == 64'h333344441111bbbb);
    r_ready = 1; tick(); r_ready = 0; assert (!r_valid);

    axi_write(32'h4004, 64'hdead_beef_0000_0000, 8'hf0, 4'h5, 2'b00);
    host_word_addr = 1; #1; assert (host_rdata == 32'hdead_beef);
    axi_write(32'h2000, 64'h0000_0000_0000_4833, 8'h0f, 4'h3, 2'b00);
    assert (result_valid && result == 32'h0000_4833);
    result_ack = 1; tick(); result_ack = 0;
    assert (!result_valid && result == 32'h0000_4833);
    axi_write(32'h3000, 64'hffff_ffff_ffff_ffff, 8'hff, 4'h7, 2'b11);

    job_active = 1;
    ar_addr = 32'h3000; ar_id = 4'h2; ar_valid = 1; tick(); ar_valid = 0;
    assert (r_valid && r_resp == 2'b00 && r_data == 1 && r_last);
    r_ready = 1; tick(); r_ready = 0;

    $display("H7_DOORBELL_AXI_PASS");
    $display("H3_AXI_SHARED_DATA_RAM_PASS");
    $finish;
  end
endmodule
