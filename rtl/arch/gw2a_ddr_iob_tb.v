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
    #20 reset <= 1'b1;
    #40 reset <= 1'b0;
  end

  reg oe_nq = 1'b1;
  reg [HSB:0] rnd_q;
  reg [MSB:0] dat_q;
  wire [HSB:0] iob_w;
  wire [MSB:0] dat_w;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("gw2a_ddr_iob_tb.vcd");
    $dumpvars;

    #800 $finish;
  end


  // -- Stimulus -- //

  reg [3:0] count;
  reg oe_pq, oe_qn, oe_q2;
  wire [3:0] cnext = count + 1;
  wire oe_nw = count > 1 && count < 6;
  wire oe_nx = count > 7 && count < 12;

  assign iob_w = ~oe_q2 ? {HBITS{1'bz}} : rnd_q;

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
    oe_q2 <= oe_pq;
    // rnd_q <= oe_q2 ? $urandom : {HBITS{1'bz}};
    oe_q2 <= ~oe_qn;
    rnd_q <= ~oe_qn ? $urandom : {HBITS{1'bz}};
  end


  // -- Simulated Module Under Test -- //

  generate
    for (genvar ii = 0; ii < HBITS; ii++) begin : gen_iobs

      gw2a_ddr_iob #(
          .SHIFT(3'b100)
      ) u_gw2a_ddr_iob (
          .PCLK(clk_x1),
          .FCLK(clk_x2),
          .RESET(reset),
          .OEN(oe_nq),
          .D0(dat_q[ii]),
          .D1(dat_q[HBITS+ii]),
          .Q0(dat_w[ii]),
          .Q1(dat_w[HBITS+ii]),
          .IO(iob_w[ii])
      );

    end
  endgenerate


endmodule  // gw2a_ddr_iob_tb
