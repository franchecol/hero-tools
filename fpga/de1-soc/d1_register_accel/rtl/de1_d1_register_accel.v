module de1_d1_register_accel (
    input  wire       CLOCK_50,
    input  wire [3:0] KEY,
    input  wire [9:0] SW,
    output wire [9:0] LEDR,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5
);

    localparam [23:0] BUSY_CYCLES = 24'd12_500_000;

    reg [7:0] operand_a = 8'h00;
    reg [7:0] operand_b = 8'h00;
    reg [7:0] result    = 8'h00;
    reg [1:0] opcode    = 2'b00;

    reg        busy         = 1'b0;
    reg        done         = 1'b0;
    reg [23:0] busy_counter = 24'd0;

    reg [3:0] key_meta   = 4'hf;
    reg [3:0] key_sync   = 4'hf;
    reg [3:0] key_sync_d = 4'hf;

    wire [3:0] key_pressed = key_sync_d & ~key_sync;

    function [7:0] compute;
        input [1:0] op;
        input [7:0] a;
        input [7:0] b;
        begin
            case (op)
                2'b00: compute = a + b;
                2'b01: compute = a ^ b;
                2'b10: compute = a & b;
                2'b11: compute = a | b;
            endcase
        end
    endfunction

    always @(posedge CLOCK_50) begin
        key_meta   <= KEY;
        key_sync   <= key_meta;
        key_sync_d <= key_sync;

        if (key_pressed[0]) begin
            operand_a     <= 8'h00;
            operand_b     <= 8'h00;
            result        <= 8'h00;
            opcode        <= 2'b00;
            busy          <= 1'b0;
            done          <= 1'b0;
            busy_counter  <= 24'd0;
        end else if (busy) begin
            if (busy_counter == 24'd0) begin
                result <= compute(opcode, operand_a, operand_b);
                busy   <= 1'b0;
                done   <= 1'b1;
            end else begin
                busy_counter <= busy_counter - 24'd1;
            end
        end else begin
            if (key_pressed[1]) begin
                operand_a <= SW[7:0];
                done      <= 1'b0;
            end

            if (key_pressed[2]) begin
                operand_b <= SW[7:0];
                done      <= 1'b0;
            end

            if (key_pressed[3]) begin
                opcode       <= SW[9:8];
                busy         <= 1'b1;
                done         <= 1'b0;
                busy_counter <= BUSY_CYCLES - 24'd1;
            end
        end
    end

    assign LEDR[7:0] = result;
    assign LEDR[8]   = done;
    assign LEDR[9]   = busy;

    hex7seg hex_result_lo (.nibble(result[3:0]),    .segments(HEX0));
    hex7seg hex_result_hi (.nibble(result[7:4]),    .segments(HEX1));
    hex7seg hex_b_lo      (.nibble(operand_b[3:0]), .segments(HEX2));
    hex7seg hex_b_hi      (.nibble(operand_b[7:4]), .segments(HEX3));
    hex7seg hex_a_lo      (.nibble(operand_a[3:0]), .segments(HEX4));
    hex7seg hex_a_hi      (.nibble(operand_a[7:4]), .segments(HEX5));

endmodule

module hex7seg (
    input  wire [3:0] nibble,
    output reg  [6:0] segments
);

    always @* begin
        case (nibble)
            4'h0: segments = 7'b1000000;
            4'h1: segments = 7'b1111001;
            4'h2: segments = 7'b0100100;
            4'h3: segments = 7'b0110000;
            4'h4: segments = 7'b0011001;
            4'h5: segments = 7'b0010010;
            4'h6: segments = 7'b0000010;
            4'h7: segments = 7'b1111000;
            4'h8: segments = 7'b0000000;
            4'h9: segments = 7'b0010000;
            4'ha: segments = 7'b0001000;
            4'hb: segments = 7'b0000011;
            4'hc: segments = 7'b1000110;
            4'hd: segments = 7'b0100001;
            4'he: segments = 7'b0000110;
            4'hf: segments = 7'b0001110;
        endcase
    end

endmodule

