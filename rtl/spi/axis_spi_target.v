`timescale 1ns / 100ps
/**
 * Transmits and receives packets via SPI.
 */
module axis_spi_target #(
    parameter RX_FIFO_SIZE = 2048,
    parameter TX_FIFO_SIZE = 2048,
    localparam RBITS = $clog2(RX_FIFO_SIZE),
    localparam TBITS = $clog2(TX_FIFO_SIZE),
    parameter WIDTH = 8,
    localparam MSB = WIDTH - 1,
    parameter [MSB:0] HEADER = 8'ha7,
    parameter SPI_CPOL = 0,  // todo: SPI clock polarity
    parameter SPI_CPHA = 0  // todo: SPI clock phase
) (
    input clock,
    input reset,

    input  SCK,
    input  SSEL,
    input  MOSI,
    output MISO,

    input [MSB-1:0] status_i,

    // Error flags from the SPI link- & phy- layer
    output overflow_o,
    output underrun_o,

    output m_tvalid_o,
    input m_tready_i,
    output [MSB:0] m_tdata_o,

    input s_tvalid_i,
    output s_tready_o,
    input s_tlast_i,
    input [MSB:0] s_tdata_i
);


  // -- Signals & State -- //

  wire tvalid_w, tready_w, tlast_w, rvalid_w, rready_w, rlast_w;
  wire [MSB:0] rdata_w, tdata_w;


  spi_target #(
      .HEADER(HEADER),
      .WIDTH (WIDTH)
  ) U_SPI_SLAVE1 (
      .clock(clock),
      .reset(reset),

      .status_i  (status_i),
      .overflow_o(overflow_o),
      .underrun_o(underrun_o),

      .m_tvalid(rvalid_w),
      .m_tready(rready_w),
      .m_tdata (rdata_w),

      .s_tvalid(tvalid_w),
      .s_tready(tready_w),
      .s_tlast (tlast_w),
      .s_tdata (tdata_w),

      .SCK_pin(SCK),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );


  //
  //  SPI Packet FIFOs
  ///
  // Buffers packets received via SPI //
  sync_fifo #(
      .OUTREG(3),
      .WIDTH (WIDTH),
      .ABITS (RBITS)
  ) U_RX_FIFO1 (
      .clock(clock),
      .reset(reset),

      .valid_i(rvalid_w),
      .ready_o(rready_w),
      .data_i (rdata_w),

      .valid_o(m_tvalid_o),
      .ready_i(m_tready_i),
      .data_o (m_tdata_o)
  );

  // Queues up data to be sent via SPI //
  packet_fifo #(
      .OUTREG(2),
      .WIDTH (WIDTH),
      .ABITS (TBITS)
  ) U_TX_FIFO1 (
      .clock(clock),
      .reset(reset),

      .valid_i(s_tvalid_i),
      .ready_o(s_tready_o),
      .last_i(s_tlast_i),
      .drop_i(1'b0),  // todo ...
      .data_i(s_tdata_i),

      .valid_o(tvalid_w),
      .ready_i(tready_w),
      .last_o (tlast_w),   // todo ...
      .data_o (tdata_w)
  );


endmodule  // axis_spi_target
