`timescale 1ns / 100ps
/**
 * Cross clock-domains by only asserting 'CE' far from clock-edges (so this has
 * to be sourced from elsewhere).
 */
module slow_ce_cdc #(
    parameter  WIDTH = 8,
    localparam MSB   = WIDTH - 1,
    parameter  DREGS = 2,
    parameter  CREGS = 2
) (
    input aclk,
    input arst,
    input aen_i,
    input [MSB:0] adat_i,
    input bclk,
    input brst,
    input ben_i,
    output [MSB:0] bdat_o
);

  reg [MSB:0] bdat_q;

  assign bdat_o = bdat_q;

  always @(posedge bclk) begin
    if (ben_i) begin
      bdat_q <= adat_i;
    end
  end

  //
  //  Todo:
  //   - measure the delay assertion delays between 'aen_i' and 'ben_i';
  //   - throw an error on setup & latching violations;
  //

  always @(posedge aclk or posedge bclk) begin
    if (!arst && !brst) begin
      if (aen_i && ben_i) begin
        $error("%5t: Naughty! (module = %m)", $time);
      end
    end
  end

endmodule  /* slow_ce_cdc */
