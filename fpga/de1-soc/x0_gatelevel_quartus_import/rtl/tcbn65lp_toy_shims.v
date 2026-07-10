// Minimal public compatibility shims for the TSMC65 cell names used by the
// toy Genus netlist.  This is not the vendor cell library.

module CKAN2D1 (
    input  wire A1,
    input  wire A2,
    output wire Z
);
    assign Z = A1 & A2;
endmodule

module CKND0 (
    input  wire I,
    output wire ZN
);
    assign ZN = ~I;
endmodule

module CKND2D0 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);
    assign ZN = ~(A1 & A2);
endmodule

module IAO21D0 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);
    assign ZN = ~(((~A1) & (~A2)) | B);
endmodule

module MOAI22D0 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);
    assign ZN = ~((A1 | A2) & ~(B1 & B2));
endmodule

module OA21D0 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire Z
);
    assign Z = (A1 | A2) & B;
endmodule

module SDFCNQD1 (
    input  wire CDN,
    input  wire CP,
    input  wire D,
    input  wire SI,
    input  wire SE,
    output reg  Q
);
    always @(posedge CP or negedge CDN) begin
        if (!CDN) begin
            Q <= 1'b0;
        end else begin
            Q <= SE ? SI : D;
        end
    end
endmodule
