`timescale 1ns / 100ps
module up_counter #(
    parameter  WIDTH = 10,
    localparam CZERO = {WIDTH{1'b0}},
    localparam CONES = {WIDTH{1'b1}},
    localparam MSB   = WIDTH - 1,
    parameter  UPPER = (1 << WIDTH) - 1,
    parameter  LOWER = CZERO,
    parameter  CLAMP = 0
) (
    input clk,
    input en,

    input inc_i,
    input store_i,
    input clear_i,
    output limit_o,
    output oflow_o,
    input [MSB:0] value_i,
    output [MSB:0] count_o
);

  reg [MSB:0] count_q;
  reg limit_q, oflow_q;
  wire oflow_w;
  wire [MSB:0] count_w;
  wire [WIDTH:0] cnext_w;

  assign count_w = store_i ? value_i : count_q;
  assign cnext_w = count_w + (CLAMP && limit_q ? 1'b0 : inc_i);
  assign oflow_w = UPPER == CONES ? cnext_w[WIDTH] : cnext_w > UPPER;

  assign limit_o = limit_q;
  assign count_o = count_q;

  always @(posedge clk) begin
    if (!en || clear_i) begin
      count_q <= LOWER;
      limit_q <= 1'b0;
      oflow_q <= 1'b0;
    end else begin
      count_q <= cnext_w[MSB:0];
      limit_q <= cnext_w == UPPER;
      oflow_q <= oflow_q | oflow_w;
    end
  end

endmodule  /* up_counter */
