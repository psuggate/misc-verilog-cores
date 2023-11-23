`timescale 1ns / 100ps
module gowin_rpll (
    clkout, // 120 MHz by default
    lock,
    clkin
);

  parameter FCLKIN = "27";
  parameter DYN_IDIV_SEL = "false";
  parameter IDIV_SEL = 8;
  parameter DYN_FBDIV_SEL = "false";
  parameter FBDIV_SEL = 39;
  parameter DYN_ODIV_SEL = "false";
  parameter ODIV_SEL = 8;
  parameter PSDA_SEL = "0000";
  parameter DYN_DA_EN = "true";
  parameter DUTYDA_SEL = "1000";
  parameter CLKOUT_FT_DIR = 1'b1;
  parameter CLKOUTP_FT_DIR = 1'b1;
  parameter CLKOUT_DLY_STEP = 0;
  parameter CLKOUTP_DLY_STEP = 0;
  parameter CLKFB_SEL = "internal";
  parameter CLKOUT_BYPASS = "false";
  parameter CLKOUTP_BYPASS = "false";
  parameter CLKOUTD_BYPASS = "false";
  parameter DYN_SDIV_SEL = 2;
  parameter CLKOUTD_SRC = "CLKOUT";
  parameter CLKOUTD3_SRC = "CLKOUT";
  parameter DEVICE = "GW2A-18C";

  output clkout;
  output lock;
  input clkin;

  wire clkoutp_o;
  wire clkoutd_o;
  wire clkoutd3_o;
  wire gw_gnd;

  assign gw_gnd = 1'b0;

  rPLL #(
      .FCLKIN(FCLKIN),
      .DYN_IDIV_SEL(DYN_IDIV_SEL),
      .IDIV_SEL(IDIV_SEL),
      .DYN_FBDIV_SEL(DYN_FBDIV_SEL),
      .FBDIV_SEL(FBDIV_SEL),
      .DYN_ODIV_SEL(DYN_ODIV_SEL),
      .ODIV_SEL(ODIV_SEL),
      .PSDA_SEL(PSDA_SEL),
      .DYN_DA_EN(DYN_DA_EN),
      .DUTYDA_SEL(DUTYDA_SEL),
      .CLKOUT_FT_DIR(CLKOUT_FT_DIR),
      .CLKOUTP_FT_DIR(CLKOUTP_FT_DIR),
      .CLKOUT_DLY_STEP(CLKOUT_DLY_STEP),
      .CLKOUTP_DLY_STEP(CLKOUTP_DLY_STEP),
      .CLKFB_SEL(CLKFB_SEL),
      .CLKOUT_BYPASS(CLKOUT_BYPASS),
      .CLKOUTP_BYPASS(CLKOUTP_BYPASS),
      .CLKOUTD_BYPASS(CLKOUTD_BYPASS),
      .DYN_SDIV_SEL(DYN_SDIV_SEL),
      .CLKOUTD_SRC(CLKOUTD_SRC),
      .CLKOUTD3_SRC(CLKOUTD3_SRC),
      .DEVICE("GW2A-18C")
  ) rpll_inst (
      .CLKOUT(clkout),
      .LOCK(lock),
      .CLKOUTP(clkoutp_o),
      .CLKOUTD(clkoutd_o),
      .CLKOUTD3(clkoutd3_o),
      .RESET(gw_gnd),
      .RESET_P(gw_gnd),
      .CLKIN(clkin),
      .CLKFB(gw_gnd),
      .FBDSEL({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
      .IDSEL({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
      .ODSEL({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
      .PSDA({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
      .DUTYDA({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
      .FDLY({gw_gnd, gw_gnd, gw_gnd, gw_gnd})
  );

endmodule  // gowin_rpll
