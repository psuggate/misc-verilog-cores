`timescale 1ns / 100ps
/**
 * AXI layer over the AXI4-Stream version.
 */
module axi_spi_slave #(
    parameter RX_FIFO_SIZE = 2048,
    parameter TX_FIFO_SIZE = 2048,
    localparam RBITS = $clog2(RX_FIFO_SIZE),
    localparam TBITS = $clog2(TX_FIFO_SIZE),
    parameter [7:0] SPI_HEADER = 8'ha7,
    parameter SPI_WIDTH = 8,
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

    output axi_awvalid_o,
    input axi_awready_i,
    output [ASB:0] axi_awaddr_o,
    output [ISB:0] axi_awid_o,
    output [7:0] axi_awlen_o,
    output [1:0] axi_awburst_o,

    output axi_wvalid_o,
    input axi_wready_i,
    output axi_wlast_o,
    output [SSB:0] axi_wstrb_o,
    output [MSB:0] axi_wdata_o,

    input axi_bvalid_i,
    output axi_bready_o,
    input [1:0] axi_bresp_i,
    input [ISB:0] axi_bid_i,

    output axi_arvalid_o,
    input axi_arready_i,
    output [ASB:0] axi_araddr_o,
    output [ISB:0] axi_arid_o,
    output [7:0] axi_arlen_o,
    output [1:0] axi_arburst_o,

    input axi_rvalid_i,
    output axi_rready_o,
    input axi_rlast_i,
    input [1:0] axi_rresp_i,
    input [ISB:0] axi_rid_i,
    input [MSB:0] axi_rdata_i
);


  // -- Signals & State -- //

  wire active_w, tready_w, tvalid_w, rvalid_nw, rvalid_w, rready_w;
  wire [7:0] rdata_w, tdata_w;
  reg rlast_q, wlast_q;

  assign rvalid_w = ~rvalid_nw;


  spi_layer #(
      .WIDTH(SPI_WIDTH)
  ) U_SPI_SLAVE1 (
      .clk_i(clock),
      .rst_i(reset),

      .cyc_o(active_w),
      .get_o(tready_w),
      .rdy_i(active_w & tvalid_w),
      .dat_i(tdata_w),

      .wat_o(rvalid_nw),
      .ack_i(active_w & rready_w),
      .dat_o(rdata_w),

      .SCK_pin(SCK),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );


  //
  //  SPI Packet FIFOs
  ///
  packet_fifo #(
      .OUTREG(2),
      .WIDTH (8),
      .ABITS (RBITS)
  ) U_RX_FIFO1 (
      .clock(clock),
      .reset(reset),

      .valid_i(active_w & rvalid_w),
      .ready_o(rready_w),
      .last_i(rlast_q),
      .drop_i(1'b0),  // todo ...
      .data_i(rdata_w),

      .valid_o(axi_wvalid_o),
      .ready_i(axi_wready_i),
      .last_o (axi_wlast_o),
      .data_o (axi_wdata_o)
  );

  packet_fifo #(
      .OUTREG(2),
      .WIDTH (8),
      .ABITS (TBITS)
  ) U_TX_FIFO1 (
      .clock(clock),
      .reset(reset),

      .valid_i(axi_rvalid_i),
      .ready_o(axi_rready_o),
      .last_i(axi_rlast_i),
      .drop_i(1'b0),  // todo ...
      .data_i(axi_rdata_i),

      .valid_o(tvalid_w),
      .ready_i(active_w & tready_w),
      .last_o(),  // todo ...
      .data_o(tdata_w)
  );


endmodule  // axi_spi_slave
