`timescale 1ns / 100ps
module gw2a_ddr_iob (
    PCLK,
    FCLK,
    RESET,
    //  CALIB,
    OEN,
    D0,
    D1,
    Q0,
    Q1,
    IO,
    IOB
);

  parameter [2:0] SHIFT = 3'b000;
  parameter TLVDS = 1'b0;

  input PCLK;
  input FCLK;
  input RESET;
  // input CALIB;
  input OEN;
  input D0;
  input D1;
  output Q0;
  output Q1;
  inout IO;
  inout IOB;


  reg q0_r, q1_r, d0_q;
  wire d_iw, di0_w, di1_w, di2_w, di3_w, d_ow, t_w;
  wire CALIB = 1'b0;

  assign Q0 = SHIFT[2] ? d0_q : q0_r;
  assign Q1 = SHIFT[2] ? q0_r : q1_r;


  always @* begin
    case (SHIFT[1:0])
      default: {q0_r, q1_r} = {di0_w, di2_w};
      2'b01:   {q0_r, q1_r} = {di1_w, di3_w};
      2'b10:   {q0_r, q1_r} = {di2_w, di0_w};
      2'b11:   {q0_r, q1_r} = {di3_w, di1_w};
    endcase
  end

  always @(posedge PCLK) begin
    d0_q <= q1_r;
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


  OSER4 u_oser4 (
      .FCLK(FCLK),
      .PCLK(PCLK),
      .RESET(RESET),
      .TX0(OEN),
      .TX1(OEN),
      .D0(D0),
      .D1(D0),
      .D2(D1),
      .D3(D1),
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


endmodule  // gw2a_ddr_iob
