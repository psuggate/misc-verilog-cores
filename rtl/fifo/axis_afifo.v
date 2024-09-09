`timescale 1ns / 100ps
/**
 * Simple, asynchronous FIFO that uses the (small) LUT SRAMs of an FPGA; e.g.
 * Xilinx "distributed" SRAMs, or GoWin "shadow" SRAMs.
 */
module axis_afifo #(
    parameter TLAST = 1,
    parameter integer WIDTH = 8,
    localparam MSB = WIDTH - 1,
    localparam FSB = WIDTH + TLAST - 1,
    parameter integer ABITS = 4,
    parameter integer DELAY = 3
) (
    input aresetn,

    input s_aclk,
    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [MSB:0] s_tdata,

    input m_aclk,
    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [MSB:0] m_tdata
);

  wire wr_full, rd_empty;
  wire fetch_w, store_w;
  wire [WIDTH:0] wdata_w, rdata_w;

  initial begin
    if (TLAST != 0 && TLAST != 1) begin
      $error("Error: Invalid 'TLAST' value: %d (instance %m)", TLAST);
      $finish;
    end
  end

  assign s_tready = ~wr_full;
  assign m_tvalid = ~rd_empty;

  assign store_w = s_tvalid & ~wr_full;
  assign wdata_w = {s_tlast, s_tdata};
  assign fetch_w = m_tready & ~rd_empty;
  assign {m_tlast, m_tdata} = rdata_w;

  afifo_gray #(
      .WIDTH(WIDTH + TLAST),
      .ABITS(ABITS),
      .DELAY(DELAY)
  ) AFIFO0 (
      // Asynchronous reset:
      .reset_ni (aresetn),

      // Write clock domain:
      .wr_clk_i (s_aclk),
      .wr_en_i  (store_w),
      .wr_data_i(wdata_w[FSB:0]),
      .wfull_o  (wr_full),

      // Read clock domain:
      .rd_clk_i (m_aclk),
      .rd_en_i  (fetch_w),
      .rd_data_o(rdata_w[FSB:0]),
      .rempty_o (rd_empty)
  );

endmodule  // axis_afifo
