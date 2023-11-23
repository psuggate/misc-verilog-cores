`timescale 1ns / 100ps
module shift_register (
    clock,
    wren_i,
    addr_i,
    data_i,
    data_o
);

  parameter WIDTH = 8;
  localparam MSB = WIDTH - 1;

  parameter DEPTH = 16;
  localparam ASB = $clog2(DEPTH) - 1;

  input clock;
  input wren_i;
  input [ASB:0] addr_i;
  input [MSB:0] data_i;
  output [MSB:0] data_o;

  reg [MSB:0] data_q;

  assign data_o = data_q;

  genvar ii;
  generate
    begin : g_shift

      // begin : g_shift_register
      reg [MSB:0] srl[0:DEPTH-1];

      for (ii = 0; ii < DEPTH - 1; ii = ii + 1) begin : g_forshi
        always @(posedge clock) begin
          if (wren_i) begin
            srl[ii+1] <= srl[ii];
          end
        end
      end

      always @(posedge clock) begin
        if (wren_i) begin
          srl[0] <= data_i;
        end

        data_q <= srl[addr_i];
      end

    end
  endgenerate  // g_shift_register

endmodule  // shift_register
