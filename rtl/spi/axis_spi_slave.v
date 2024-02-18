`timescale 1ns / 100ps
module axis_spi_slave #(
    parameter RX_FIFO_SIZE = 2048,
    parameter TX_FIFO_SIZE = 2048,
    localparam RBITS = $clog2(RX_FIFO_SIZE),
    localparam TBITS = $clog2(TX_FIFO_SIZE),
    parameter SPI_CPOL = 0,  // SPI clock polarity
    parameter SPI_CPHA = 0,  // SPI clock phase
    parameter AXI_WIDTH = 8,
    parameter AXI_STRBS = AXI_WIDTH / 8,
    parameter AXI_ADDRS = 16,
    parameter AXI_IBITS = 4,
    localparam MSB = AXI_WIDTH - 1,
    localparam SSB = AXI_STRBS - 1,
    localparam ASB = AXI_ADDRS - 1,
    localparam ISB = AXI_IBITS - 1
) (
    input clock,
    input reset,

    input  SCK,
    input  SSEL,
    input  MOSI,
    output MISO,

    input axi_awvalid_i,
    output axi_awready_o,
    input [ASB:0] axi_awaddr_i,
    input [ISB:0] axi_awid_i,
    input [7:0] axi_awlen_i,
    input [1:0] axi_awburst_i,

    input axi_wvalid_i,
    output axi_wready_o,
    input axi_wlast_i,
    input [SSB:0] axi_wstrb_i,
    input [MSB:0] axi_wdata_i,

    output axi_bvalid_o,
    input axi_bready_i,
    output [1:0] axi_bresp_o,
    output [ISB:0] axi_bid_o,

    input axi_arvalid_i,
    output axi_arready_o,
    input [ASB:0] axi_araddr_i,
    input [ISB:0] axi_arid_i,
    input [7:0] axi_arlen_i,
    input [1:0] axi_arburst_i,

    output axi_rvalid_o,
    input axi_rready_i,
    output axi_rlast_o,
    output [1:0] axi_rresp_o,
    output [ISB:0] axi_rid_o,
    output [MSB:0] axi_rdata_o
);


  spi_slave U_SPI_SLAVE1 ();


  //
  //  SPI Packet FIFOs
  ///
  packet_fifo #(
      .OUTREGS(2),
      .WIDTH  (8),
      .ABITS  (RBITS)
  ) U_RX_FIFO1 ();

  packet_fifo #(
      .OUTREGS(2),
      .WIDTH  (8),
      .ABITS  (TBITS)
  ) U_TX_FIFO1 ();


endmodule  // axis_spi_slave
