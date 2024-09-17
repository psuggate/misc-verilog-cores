`timescale 1ns / 100ps
module gw2a_ddr_iob_tb;

  localparam WIDTH = 8;
  localparam HBITS = WIDTH / 2;
  localparam MSB = WIDTH - 1;
  localparam HSB = HBITS - 1;

  reg clk_x1 = 1'b1;
  reg clk_x2 = 1'b1;
  reg clk_x4 = 1'b1;
  reg reset = 1'bx;

  always #1.25 clk_x4 <= ~clk_x4;
  always #2.50 clk_x2 <= ~clk_x2;
  always #5.00 clk_x1 <= ~clk_x1;

  initial begin
    #10 reset <= 1'b1;
    #20 reset <= 1'b0;
  end

  reg oe_nq = 1'b1;
  reg [HSB:0] rnd_q, rnd_p;
  reg [MSB:0] dat_q;
  wire [MSB:0] sh0_w, sh1_w, sh2_w, sh3_w;
  wire [HSB:0] io0_w, io1_w, io2_w, io3_w;
  wire [HSB:0] iq0_w, iq1_w, iq2_w, iq3_w;

  // -- Simulation Data -- //

  initial begin
    $dumpfile("gw2a_ddr_iob_tb.vcd");
    $dumpvars;

    #1600 $finish;
  end

  // -- Stimulus -- //

  reg [3:0] count;
  reg oe_pq, oe_qn, oe_q2, oe_q3, oe_q4;
  wire [3:0] cnext = count + 1;
  wire oe_nw = count > 1 && count < 6;
  wire oe_nx = count > 7 && count < 12;

  assign io0_w = ~oe_q4 ? {HBITS{1'bz}} : rnd_p;
  assign io1_w = ~oe_q4 ? {HBITS{1'bz}} : rnd_q;
  assign io2_w = ~oe_q4 ? {HBITS{1'bz}} : rnd_p;
  assign io3_w = ~oe_q4 ? {HBITS{1'bz}} : rnd_q;

  assign iq0_w = clk_x1 ? sh0_w[HSB:0] : sh0_w[MSB:HBITS];
  assign iq1_w = clk_x1 ? sh1_w[HSB:0] : sh1_w[MSB:HBITS];
  assign iq2_w = clk_x1 ? sh2_w[HSB:0] : sh2_w[MSB:HBITS];
  assign iq3_w = clk_x1 ? sh3_w[HSB:0] : sh3_w[MSB:HBITS];

  always @(posedge clk_x1) begin
    if (reset) begin
      oe_nq <= 1'b1;
      oe_pq <= 1'b0;
      oe_qn <= 1'b1;
      count <= 0;
      dat_q <= {WIDTH{1'bz}};
    end else begin
      count <= cnext;
      oe_nq <= ~oe_nw;
      oe_pq <= oe_nx;
      oe_qn <= ~oe_pq;
      dat_q <= oe_nw ? $urandom : {WIDTH{1'bz}};
    end
  end

  always @(posedge clk_x2) begin
    oe_q2 <= ~oe_qn;
    oe_q3 <= oe_q2;
    oe_q4 <= oe_q3;
    rnd_p <= oe_q3 ? $urandom : {HBITS{1'bz}};
  end

  always @(negedge clk_x2) begin
    rnd_q <= rnd_p;
  end

  // -- Simulated Module Under Test -- //

  generate
    for (genvar ii = 0; ii < HBITS; ii++) begin : gen_iobs

      gw2a_ddr_iob #(
          .WRDLY(0)
      ) u_ddr_sh0 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .SHIFT(2'd0),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh0_w[ii]),
          .Q1(sh0_w[HBITS+ii]),
          .IO(io0_w[ii])
      );

      gw2a_ddr_iob #(
          .WRDLY(1)
      ) u_ddr_sh1 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .SHIFT(2'd1),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh1_w[ii]),
          .Q1(sh1_w[HBITS+ii]),
          .IO(io1_w[ii])
      );

      gw2a_ddr_iob #(
          .WRDLY(2)
      ) u_ddr_sh2 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .SHIFT(2'd2),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh2_w[ii]),
          .Q1(sh2_w[HBITS+ii]),
          .IO(io2_w[ii])
      );

      gw2a_ddr_iob #(
          .WRDLY(3)
      ) u_ddr_sh3 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .SHIFT(2'd3),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh3_w[ii]),
          .Q1(sh3_w[HBITS+ii]),
          .IO(io3_w[ii])
      );

    end
  endgenerate

  reg D_q, D_p, CALIB, en_q;
  wire CLK_w, D_w, D_x, Q3_w, Q2_w, Q1_w, Q0_w, R1_w, R0_w, S1_w, S0_w;
  wire en_w, U1_w, U0_w, T1_w, T0_w;

  initial begin
    #10 CALIB = 1'b0;
    /*
    #20 CALIB = 1'b1;
    #10 CALIB = 1'b0;
    #10 CALIB = 1'b1;
    #10 CALIB = 1'b0;
    #10 CALIB = 1'b1;
    #10 CALIB = 1'b0;
    */
    // #10 CALIB = 1'b1; // Wraps back to 0-offset
    // #10 CALIB = 1'b0;
  end

  assign CLK_w = clk_x2 ^ clk_x1;
  assign #1 D_w = CLK_w ? D_q : D_p;
  assign en_w = oe_q3;
  assign D_x = ~D_w;

  always @(posedge clk_x2) begin
    if (en_w) begin
      D_p <= $urandom;
    end else begin
      D_p <= 1'bz;
    end
  end

  always @(negedge clk_x2) begin
    en_q <= en_w;
    if (en_w) begin
      D_q <= $urandom;
    end else begin
      D_q <= 1'bz;
    end
  end

  IDES4 U_IDES1 (
      .PCLK(clk_x1),
      .FCLK(clk_x2),
      .RESET(reset),
      .CALIB(CALIB),
      .D(D_w),
      .Q0(Q0_w),
      .Q1(Q1_w),
      .Q2(Q2_w),
      .Q3(Q3_w)
  );

  gw2a_ddr_iob #(
      .WRDLY(0)
  ) U_DDR0 (
      .PCLK(clk_x1),
      .FCLK(clk_x2),
      .RESET(reset),
      .OEN(1'b1),
      .SHIFT(2'd0),
      .D0(1'b0),
      .D1(1'b0),
      .Q0(R0_w),
      .Q1(R1_w),
      .IO(D_w),
      .IOB(D_x)
  );

  gw2a_ddr_iob #(
      .WRDLY(0)
  ) U_DDR1 (
      .PCLK(clk_x1),
      .FCLK(clk_x2),
      .RESET(reset),
      .OEN(1'b1),
      .SHIFT(2'd1),
      .D0(1'b0),
      .D1(1'b0),
      .Q0(S0_w),
      .Q1(S1_w),
      .IO(D_w),
      .IOB(D_x)
  );

  gw2a_ddr_iob #(
      .WRDLY(0)
  ) U_DDR2 (
      .PCLK(clk_x1),
      .FCLK(clk_x2),
      .RESET(reset),
      .OEN(1'b1),
      .SHIFT(2'd2),
      .D0(1'b0),
      .D1(1'b0),
      .Q0(T0_w),
      .Q1(T1_w),
      .IO(D_w),
      .IOB(D_x)
  );

  gw2a_ddr_iob #(
      .WRDLY(0)
  ) U_DDR3 (
      .PCLK(clk_x1),
      .FCLK(clk_x2),
      .RESET(reset),
      .OEN(1'b1),
      .SHIFT(2'd3),
      .D0(1'b0),
      .D1(1'b0),
      .Q0(U0_w),
      .Q1(U1_w),
      .IO(D_w),
      .IOB(D_x)
  );

endmodule  /* gw2a_ddr_iob_tb */
