`timescale 1ns / 100ps
module mux4to1 #(
    parameter WIDTH = 8
) (
    output [WIDTH-1:0] O,
    input [1:0] S,
    input [WIDTH-1:0] I0,
    input [WIDTH-1:0] I1,
    input [WIDTH-1:0] I2,
    input [WIDTH-1:0] I3
);

  assign O = S == 2'b01 ? I1 : S == 2'b10 ? I2 : S == 2'b11 ? I3 : I0;

endmodule  // mux4to1
