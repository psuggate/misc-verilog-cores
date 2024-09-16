`timescale 1ns / 100ps
module gw2a_ddr_iob_tb;

  localparam WIDTH = 8;
  localparam HBITS = WIDTH / 2;
  localparam MSB = WIDTH - 1;
  localparam HSB = HBITS - 1;


  reg clk_x1 = 1'b1;
  reg clk_x2 = 1'b1;
  reg reset = 1'bx;

  always #2.5 clk_x2 <= ~clk_x2;
  always #5.0 clk_x1 <= ~clk_x1;

  initial begin
    #10 reset <= 1'b1;
    #20 reset <= 1'b0;
  end

  reg oe_nq = 1'b1;
  reg [HSB:0] rnd_q, rnd_p;
  reg [MSB:0] dat_q;
  wire [MSB:0] sh0_w, sh1_w, sh2_w, sh3_w, sh4_w, sh5_w, sh6_w, sh7_w;
  wire [HSB:0] io0_w, io1_w, io2_w, io3_w, io4_w, io5_w, io6_w, io7_w;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("gw2a_ddr_iob_tb.vcd");
    $dumpvars;

    #800 $finish;
  end


  // -- Stimulus -- //

  reg [3:0] count;
  reg oe_pq, oe_qn, oe_q2, oe_q3;
  wire [3:0] cnext = count + 1;
  wire oe_nw = count > 1 && count < 6;
  wire oe_nx = count > 7 && count < 12;

  assign io0_w = ~oe_q3 ? {HBITS{1'bz}} : rnd_p;
  assign io1_w = ~oe_q3 ? {HBITS{1'bz}} : rnd_q;
  assign io2_w = ~oe_q3 ? {HBITS{1'bz}} : rnd_p;
  assign io3_w = ~oe_q3 ? {HBITS{1'bz}} : rnd_q;
  assign io4_w = ~oe_q3 ? {HBITS{1'bz}} : rnd_p;

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
    // oe_q2 <= oe_pq;
    // rnd_q <= oe_q2 ? $urandom : {HBITS{1'bz}};
    oe_q2 <= ~oe_qn;
    oe_q3 <= oe_q2;
    rnd_p <= oe_q2 ? $urandom : {HBITS{1'bz}};
  end

  always @(negedge clk_x2) begin
    rnd_q <= rnd_p;
  end

  // -- Simulated Module Under Test -- //

  generate
    for (genvar ii = 0; ii < HBITS; ii++) begin : gen_iobs

      gw2a_ddr_iob #(
          .WRDLY(0),
          .SHIFT(0)
      ) u_ddr_sh0 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh0_w[ii]),
          .Q1(sh0_w[HBITS+ii]),
          .IO(io0_w[ii])
      );

      gw2a_ddr_iob #(
          .WRDLY(1),
          .SHIFT(1)
      ) u_ddr_sh1 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh1_w[ii]),
          .Q1(sh1_w[HBITS+ii]),
          .IO(io1_w[ii])
      );

      gw2a_ddr_iob #(
          .WRDLY(2),
          .SHIFT(2)
      ) u_ddr_sh2 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh2_w[ii]),
          .Q1(sh2_w[HBITS+ii]),
          .IO(io2_w[ii])
      );

      gw2a_ddr_iob #(
          .WRDLY(3),
          .SHIFT(3)
      ) u_ddr_sh3 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh3_w[ii]),
          .Q1(sh3_w[HBITS+ii]),
          .IO(io3_w[ii])
      );

      gw2a_ddr_iob #(
          .WRDLY(4),
          .SHIFT(4)
      ) u_ddr_sh4 (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(sh4_w[ii]),
          .Q1(sh4_w[HBITS+ii]),
          .IO(io4_w[ii])
      );

    end
  endgenerate


endmodule  // gw2a_ddr_iob_tb
