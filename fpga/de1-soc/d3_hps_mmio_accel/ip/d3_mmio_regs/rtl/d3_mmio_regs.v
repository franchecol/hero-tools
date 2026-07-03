module d3_mmio_regs (
    input  wire        clk,
    input  wire        reset,

    input  wire [3:0]  avs_address,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    output wire        avs_waitrequest,

    output wire [9:0]  ledr,
    output wire [6:0]  hex0,
    output wire [6:0]  hex1,
    output wire [6:0]  hex2,
    output wire [6:0]  hex3,
    output wire [6:0]  hex4,
    output wire [6:0]  hex5
);

    localparam [31:0] ID_VALUE    = 32'h4433_0001;
    localparam [23:0] BUSY_CYCLES = 24'd5_000_000;

    localparam [3:0] REG_ID      = 4'h0;
    localparam [3:0] REG_CONTROL = 4'h1;
    localparam [3:0] REG_STATUS  = 4'h2;
    localparam [3:0] REG_A       = 4'h3;
    localparam [3:0] REG_B       = 4'h4;
    localparam [3:0] REG_OPCODE  = 4'h5;
    localparam [3:0] REG_RESULT  = 4'h6;
    localparam [3:0] REG_CYCLES  = 4'h7;

    reg [7:0]  operand_a    = 8'h00;
    reg [7:0]  operand_b    = 8'h00;
    reg [7:0]  result       = 8'h00;
    reg [1:0]  opcode       = 2'b00;
    reg        busy         = 1'b0;
    reg        done         = 1'b0;
    reg [23:0] busy_counter = 24'd0;
    reg [31:0] start_count  = 32'd0;

    assign avs_waitrequest = 1'b0;

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

    wire write_control = avs_write && avs_byteenable[0] && (avs_address == REG_CONTROL);
    wire write_a       = avs_write && avs_byteenable[0] && (avs_address == REG_A);
    wire write_b       = avs_write && avs_byteenable[0] && (avs_address == REG_B);
    wire write_opcode  = avs_write && avs_byteenable[0] && (avs_address == REG_OPCODE);

    wire clear_cmd = write_control && avs_writedata[1];
    wire start_cmd = write_control && avs_writedata[0] && !busy;

    always @(posedge clk) begin
        if (reset || clear_cmd) begin
            operand_a    <= 8'h00;
            operand_b    <= 8'h00;
            result       <= 8'h00;
            opcode       <= 2'b00;
            busy         <= 1'b0;
            done         <= 1'b0;
            busy_counter <= 24'd0;
            start_count  <= 32'd0;
        end else begin
            if (!busy) begin
                if (write_a) begin
                    operand_a <= avs_writedata[7:0];
                    done      <= 1'b0;
                end

                if (write_b) begin
                    operand_b <= avs_writedata[7:0];
                    done      <= 1'b0;
                end

                if (write_opcode) begin
                    opcode <= avs_writedata[1:0];
                    done   <= 1'b0;
                end

                if (start_cmd) begin
                    busy         <= 1'b1;
                    done         <= 1'b0;
                    busy_counter <= BUSY_CYCLES - 24'd1;
                    start_count  <= start_count + 32'd1;
                end
            end else if (busy_counter == 24'd0) begin
                result <= compute(opcode, operand_a, operand_b);
                busy   <= 1'b0;
                done   <= 1'b1;
            end else begin
                busy_counter <= busy_counter - 24'd1;
            end
        end
    end

    always @* begin
        case (avs_address)
            REG_ID:      avs_readdata = ID_VALUE;
            REG_CONTROL: avs_readdata = 32'h0000_0000;
            REG_STATUS:  avs_readdata = {30'd0, busy, done};
            REG_A:       avs_readdata = {24'd0, operand_a};
            REG_B:       avs_readdata = {24'd0, operand_b};
            REG_OPCODE:  avs_readdata = {30'd0, opcode};
            REG_RESULT:  avs_readdata = {24'd0, result};
            REG_CYCLES:  avs_readdata = start_count;
            default:     avs_readdata = 32'h0000_0000;
        endcase
    end

    assign ledr[7:0] = result;
    assign ledr[8]   = done;
    assign ledr[9]   = busy;

    hex7seg hex_result_lo (.nibble(result[3:0]),    .segments(hex0));
    hex7seg hex_result_hi (.nibble(result[7:4]),    .segments(hex1));
    hex7seg hex_b_lo      (.nibble(operand_b[3:0]), .segments(hex2));
    hex7seg hex_b_hi      (.nibble(operand_b[7:4]), .segments(hex3));
    hex7seg hex_a_lo      (.nibble(operand_a[3:0]), .segments(hex4));
    hex7seg hex_a_hi      (.nibble(operand_a[7:4]), .segments(hex5));

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
