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
    output m_tkeep,
    output [7:0] m_tdata,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input s_tkeep,
    input [7:0] s_tdata
);


  // -- Signals & State -- //

  wire xvalid, xready, xlast, xkeep;
  wire rvalid, rready, rlast, rkeep;
  wire [7:0] xdata, rdata;


  axis_afifo #(
      .WIDTH(9),
      .ABITS(4)
  ) U_TX_FIFO1 (
      .s_aresetn(ARSTn),

      .s_aclk(clock),
      .s_tvalid_i(s_tvalid),
      .s_tready_o(s_tready),
      .s_tlast_i(s_tlast),
      .s_tdata_i({s_tkeep, s_tdata}),

      .m_aclk    (SCK),
      .m_tvalid_o(xvalid),
      .m_tready_i(xready),
      .m_tlast_o (xlast),
      .m_tdata_o ({xkeep, xdata})
  );

  assign m_tkeep = m_tvalid;

  axis_afifo #(
      .WIDTH(8),
      .ABITS(4)
  ) RX_FIFO1 (
      .s_aresetn(ARSTn),

      .s_aclk(SCK),
      .s_tvalid_i(rvalid),
      .s_tready_o(rready),
      .s_tlast_i(rlast),
      .s_tdata_i(rdata),

      .m_aclk    (clock),
      .m_tvalid_o(m_tvalid),
      .m_tready_i(m_tready),
      .m_tlast_o (m_tlast),
      .m_tdata_o (m_tdata)
  );


  //-------------------------------------------------------------------------
  //  SPI master, and the domain-crossing subcircuits, of the interface.
  //-------------------------------------------------------------------------
  spi_master #(
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_MASTER1 (
      .clock(SCK),
      .reset(ARSTn),

      .s_tvalid(xvalid),
      .s_tready(xready),
      .s_tlast (xlast),
      .s_tkeep (xkeep),
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
