`timescale 1ns/1ps

module de1_s19_genus_snitch_data_ram_tb;
  logic CLOCK_50;
  logic [0:0] KEY;
  logic [9:0] LEDR;

  de1_s19_genus_snitch_data_ram dut (.*);

  initial begin
    CLOCK_50 = 1'b0;
    forever #10 CLOCK_50 = ~CLOCK_50;
  end

  initial begin
    KEY[0] = 1'b0;
    repeat (4) @(posedge CLOCK_50);
    KEY[0] = 1'b1;
    repeat (80) @(posedge CLOCK_50);

    if (dut.ram_q[0] !== 32'h0000_00a5) begin
      $fatal(1, "FAIL: expected RAM[0]=0x000000a5, got 0x%08h",
             dut.ram_q[0]);
    end
    if (LEDR !== 10'h3a5) begin
      $fatal(1, "FAIL: expected PASS LEDR=0x3a5, got 0x%03h", LEDR);
    end

    $display("PASS: Genus Snitch stored and loaded RAM[0]=0x%08h; LEDR=0x%03h",
             dut.ram_q[0], LEDR);
    $finish;
  end
endmodule
