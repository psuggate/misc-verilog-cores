`timescale 1ns / 100ps
module gw2a_ddr_iob #(
    parameter [1:0] WRDLY = 2'b00,
    parameter TLVDS = 1'b0
) (
    input PCLK,
    input FCLK,
    input RESET,
    input [1:0] SHIFT,
    input OEN,
    input D0,
    input D1,
    output Q0,
    output Q1,
    inout IO,
    inout IOB
);

  wire D0_w, D1_w, D2_w, D3_w, TX0_w, TX1_w;
  wire d_iw, d_ow, t_w;
  reg CALIB, D1_q, OEN_q;
  reg [1:0] shift;

  assign D0_w  = WRDLY[0] ? D1_q : D0;
  assign D1_w  = D0;
  assign D2_w  = WRDLY[0] ? D0 : D1;
  assign D3_w  = D1;

  assign TX0_w = WRDLY[0] ? OEN_q : OEN;
  assign TX1_w = OEN;

  always @(posedge PCLK) begin
    D1_q  <= D1;
    OEN_q <= OEN;
  end

  OSER4 #(
      .HWL(WRDLY[1] ? "true" : "false"),  // Causes output to be delayed half-PCLK
      .TXCLK_POL(WRDLY[0])  // Advances OE by PCLK quadrant
  ) u_oser4 (
      .FCLK(FCLK),  // Fast (x2) clock
      .PCLK(PCLK),  // Bus (x1) clock
      .RESET(RESET),
      .TX0(TX0_w),
      .TX1(TX1_w),
      .D0(D0_w),
      .D1(D1_w),
      .D2(D2_w),
      .D3(D3_w),
      .Q0(d_ow),
      .Q1(t_w)
  );

  // Advance the internal shifter of the IDES4 until it matches the desired
  // SHIFT-value.
  always @(posedge PCLK or posedge RESET) begin
    if (RESET) begin
      CALIB <= 1'b0;
      shift <= 2'd0;
    end else if (CALIB) begin
      CALIB <= 1'b0;
      shift <= shift + 1;
    end else if (shift != SHIFT[1:0]) begin
      CALIB <= 1'b1;
      shift <= shift;
    end
  end

  IDES4 u_ides4 (
      .FCLK(FCLK),
      .PCLK(PCLK),
      .RESET(RESET),
      .CALIB(CALIB),
      .D(d_iw),
      .Q0(Q0),
      .Q1(),
      .Q2(Q1),
      .Q3()
  );

  generate
    if (TLVDS == 1'b1) begin : g_tlvds

      TLVDS_IOBUF u_tlvds (
          .I  (d_ow),
          .OEN(t_w),
          .O  (d_iw),
          .IO (IO),
          .IOB(IOB)
      );

    end else begin

      assign IOB = 1'bz;

      IOBUF u_iobuf (
          .I  (d_ow),
          .OEN(t_w),
          .IO (IO),
          .O  (d_iw)
      );

    end  // !g_tlvds
  endgenerate

endmodule  /* gw2a_ddr_iob */
