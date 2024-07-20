`timescale 1ns / 100ps
module ulpi_shell
  ( input clock,
    input rst_n,
    output reg dir,
    output reg nxt,
    input stp,
    inout [7:0] data
    );

  reg dir_q;
  reg [7:0] dat_q;

  assign data = dir_q ? dat_q : 8'bz;

  initial begin
    $ulpi_step(clock, rst_n, dir, nxt, stp, data, dat_q);
  end

  always @(negedge clock) begin
    if (!rst_n) begin
      dir_q <= 1'b0;
    end else begin
      dir_q <= dir;
    end
  end

endmodule  /* ulpi_shell */
