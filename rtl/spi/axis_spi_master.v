`timescale 1ns / 100ps
/**
 * Transmits and receives packets via SPI.
 */
module axis_spi_master #(
    parameter SPI_CPOL = 0,  // todo: SPI clock polarity
    parameter SPI_CPHA = 0   // todo: SPI clock phase
) (
    input clock,
    input reset,

    input  SCK,
    input  ARSTn,
    output SCK_en,
    output SSEL,
    output MOSI,
    input  MISO,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [7:0] m_tdata,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [7:0] s_tdata
);

  // -- Signals & State -- //

  wire xvalid, xready, xlast;
  wire rvalid, rready, rlast;
  wire [7:0] xdata, rdata;

  axis_afifo #(
      .WIDTH(8),
      .ABITS(4)
  ) U_TX_FIFO1 (
      .aresetn (ARSTn),

      .s_aclk  (clock),
      .s_tvalid(s_tvalid),
      .s_tready(s_tready),
      .s_tlast (s_tlast),
      .s_tdata (s_tdata),

      .m_aclk  (SCK),
      .m_tvalid(xvalid),
      .m_tready(xready),
      .m_tlast (xlast),
      .m_tdata (xdata)
  );

  axis_afifo #(
      .WIDTH(8),
      .ABITS(4)
  ) RX_FIFO1 (
      .aresetn (ARSTn),

      .s_aclk  (SCK),
      .s_tvalid(rvalid),
      .s_tready(rready),
      .s_tlast (rlast),
      .s_tdata (rdata),

      .m_aclk  (clock),
      .m_tvalid(m_tvalid),
      .m_tready(m_tready),
      .m_tlast (m_tlast),
      .m_tdata (m_tdata)
  );


  //-------------------------------------------------------------------------
  //  SPI master, and the domain-crossing subcircuits, of the interface.
  //-------------------------------------------------------------------------
  spi_master #(
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_MASTER1 (
      .clock(SCK),
      .reset(~ARSTn),

      .s_tvalid(xvalid),
      .s_tready(xready),
      .s_tlast (xlast),
      .s_tdata (xdata),

      .m_tvalid(rvalid),
      .m_tready(rready),
      .m_tlast (rlast),
      .m_tdata (rdata),

      .SCK_en(SCK_en),
      .SSEL  (SSEL),
      .MOSI  (MOSI),
      .MISO  (MISO)
  );


endmodule  // axis_spi_master
