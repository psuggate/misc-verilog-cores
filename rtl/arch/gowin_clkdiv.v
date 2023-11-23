`timescale 1ns / 100ps
module gowin_clkdiv (
    clkout,
    hclkin,
    resetn
);

  parameter DIV_MODE = "5";

  localparam GSREN = "false";

  output clkout;
  input hclkin;
  input resetn;

  wire gw_gnd;

  assign gw_gnd = 1'b0;

  CLKDIV #(
      .DIV_MODE(DIV_MODE),
      .GSREN(GSREN)
  ) clkdiv_inst (
      .CLKOUT(clkout),
      .HCLKIN(hclkin),
      .RESETN(resetn),
      .CALIB (gw_gnd)
  );

endmodule  // gowin_clkdiv
