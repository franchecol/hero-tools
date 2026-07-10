module toy_counter_tb;
    logic       clk_i;
    logic       rst_ni;
    logic       en_i;
    logic [7:0] count_o;

    toy_counter dut (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .en_i    (en_i),
        .count_o (count_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    initial begin
        rst_ni = 1'b0;
        en_i = 1'b0;
        repeat (2) @(posedge clk_i);

        rst_ni = 1'b1;
        en_i = 1'b1;
        repeat (3) @(posedge clk_i);

        if (count_o !== 8'd3) begin
            $display("FAIL count=%0d", count_o);
            $finish;
        end

        $display("PASS count=%0d", count_o);
        $finish;
    end
endmodule
