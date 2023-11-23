`timescale 1ns / 100ps
module axis_afifo (
    s_aresetn,

    s_aclk,
    s_tvalid_i,
    s_tready_o,
    s_tlast_i,
    s_tdata_i,

    m_aclk,
    m_tvalid_o,
    m_tready_i,
    m_tlast_o,
    m_tdata_o
);

  parameter integer WIDTH = 8;
  parameter integer ABITS = 4;
  parameter integer ASIZE = 1 << ABITS;
  parameter integer DELAY = 3;

  localparam MSB = WIDTH - 1;

  input s_aresetn;

  input s_aclk;
  input s_tvalid_i;
  output s_tready_o;
  input s_tlast_i;
  input [MSB:0] s_tdata_i;

  input m_aclk;
  output m_tvalid_o;
  input m_tready_i;
  output m_tlast_o;
  output [MSB:0] m_tdata_o;

  wire wr_full, rd_empty;

  assign s_tready_o = ~wr_full;
  assign m_tvalid_o = ~rd_empty;

  afifo_gray #(
      .WIDTH(WIDTH + 1),
      .ABITS(ABITS),
      .ASIZE(ASIZE),
      .DELAY(DELAY)
  ) AFIFO0 (
      // Asynchronous reset:
      .reset_ni(s_aresetn),

      // Write clock domain:
      .wr_clk_i (s_aclk),
      .wr_en_i  (s_tvalid_i & ~wr_full),
      .wr_data_i({s_tlast_i, s_tdata_i}),
      .wfull_o  (wr_full),

      // Read clock domain:
      .rd_clk_i (m_aclk),
      .rd_en_i  (m_tready_i & ~rd_empty),
      .rd_data_o({m_tlast_o, m_tdata_o}),
      .rempty_o (rd_empty)
  );

endmodule  // axis_afifo
