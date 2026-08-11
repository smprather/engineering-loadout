// 4-bit adder with carry in and carry out.
//
// `yosys -V` prints a version banner even from an install whose
// share/yosys techlib tree is missing, so the packaging smoke must
// actually SYNTHESISE -- otherwise a broken runtime goes unnoticed.
module adder4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,
    output wire [3:0] sum,
    output wire       cout
);
    wire [4:0] tmp;
    assign tmp = {1'b0, a} + {1'b0, b} + cin;
    assign sum  = tmp[3:0];
    assign cout = tmp[4];
endmodule