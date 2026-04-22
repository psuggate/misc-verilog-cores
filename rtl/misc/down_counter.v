`timescale 1ns / 100ps
module down_counter #(
    parameter  WIDTH = 10,
    localparam CZERO = {WIDTH{1'b0}},
    localparam MSB   = WIDTH - 1,
    parameter  UPPER = (1 << WIDTH) - 1,
    parameter  LOWER = CZERO,
    parameter  CLAMP = 0
) (
    input clk,
    input en,

    input dec_i,
    input store_i,
    input clear_i,
    output limit_o,
    output uflow_o,
    input [MSB:0] value_i,
    output [MSB:0] count_o
);

  reg [MSB:0] count_q;
  reg limit_q, uflow_q;
  wire uflow_w;
  wire [MSB:0] count_w;
  wire [WIDTH:0] cprev_w;

  assign count_w = store_i ? value_i : count_q;
  assign cprev_w = count_w - (CLAMP && limit_q ? 1'b0 : dec_i);
  assign uflow_w = LOWER == CZERO ? cprev_w[WIDTH] : cprev_w < LOWER;

  assign limit_o = limit_q;
  assign uflow_o = uflow_q;
  assign count_o = count_q;

  always @(posedge clk) begin
    if (!en || clear_i) begin
      count_q <= UPPER;
      limit_q <= 1'b0;
      uflow_q <= 1'b0;
    end else begin
      count_q <= cprev_w[MSB:0];
      limit_q <= cprev_w == LOWER;
      uflow_q <= uflow_q | uflow_w;
    end
  end

endmodule  /* down_counter */
