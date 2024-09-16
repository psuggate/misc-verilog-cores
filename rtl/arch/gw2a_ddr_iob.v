`timescale 1ns / 100ps
module gw2a_ddr_iob #(
    parameter [2:0] SHIFT = 3'b000,
    parameter [1:0] WRDLY = 2'b00,
    parameter TLVDS = 1'b0
) (
    input  PCLK,
    input  FCLK,
    input  RESET,
    // input CALIB,
    input  OEN,
    input  D0,
    input  D1,
    output Q0,
    output Q1,
    inout  IO,
    inout  IOB
);

  reg q0_r, q1_r, d0_q;
  wire d_iw, di0_w, di1_w, di2_w, di3_w, d_ow, t_w, Q0_w, Q1_w;
  wire CALIB = 1'b0;

  // assign Q0 = SHIFT[2] ? d0_q : q0_r; // Orig
  // assign Q1 = SHIFT[2] ? q0_r : q1_r; // Orig

  assign Q0_w = SHIFT[2] ? d0_q : q0_r;
  assign Q1_w = SHIFT[2] ? q0_r : q1_r;

  assign Q0 = SHIFT[1] ? Q1_w : Q0_w;
  assign Q1 = SHIFT[1] ? Q0_w : Q1_w;

  always @* begin
    case (SHIFT[1:0])
      default: {q0_r, q1_r} = {di0_w, di2_w};
      2'b01:   {q0_r, q1_r} = {di1_w, di3_w};
      2'b10:   {q0_r, q1_r} = {di2_w, di0_w};
      2'b11:   {q0_r, q1_r} = {di3_w, di1_w};
    endcase
  end

  always @(posedge PCLK) begin
    d0_q <= q1_r; // Orig
  end

  IDES4 u_ides4 (
      .FCLK(FCLK),
      .PCLK(PCLK),
      .RESET(RESET),
      .CALIB(CALIB),
      .D(d_iw),
      .Q0(di0_w),
      .Q1(di1_w),
      .Q2(di2_w),
      .Q3(di3_w)
  );

  wire D0_w, D1_w, D2_w, D3_w, TX0_w, TX1_w;
  reg D0_q, D1_q, D2_q, D3_q, OEN_q;

  assign D0_w = WRDLY[0] ? D1_q : D0;
  assign D1_w = D0;
  assign D2_w = WRDLY[0] ? D0 : D1;
  assign D3_w = D1;

  assign TX0_w = WRDLY[0] ? OEN_q : OEN;
  assign TX1_w = OEN;
 
  always @(posedge PCLK) begin
    {D3_q, D2_q, D1_q, D0_q} <= {D1_q, D0_q, D1, D0};
    OEN_q <= OEN;
  end

  OSER4 #(
      .HWL(WRDLY[1] ? "true" : "false"), // Causes output to be delayed half-PCLK
      .TXCLK_POL(WRDLY[0]) // Advances OE by PCLK quadrant
  ) u_oser4 (
      .FCLK(FCLK), // Fast (x2) clock
      .PCLK(PCLK), // Bus (x1) clock
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
