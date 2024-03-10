`timescale 1ns / 100ps
module spi_to_spi #(
    parameter SPI_CPOL = 0,
    parameter SPI_CPHA = 0,
    parameter [6:0] HEADER = 7'h27
) (
    input clock,
    input reset,
    input SCK,

    output overflow_o,
    output underrun_o,

   // SPI master TX & RX ports
    input master_tx_tvalid,
    output master_tx_tready,
    input master_tx_tlast,
    input [7:0] master_tx_tdata,

    output master_rx_tvalid,
    input master_rx_tready,
    output master_rx_tlast,
    output [7:0] master_rx_tdata,

   // SPI target TX & RX ports
    input target_tx_tvalid,
    output target_tx_tready,
    input target_tx_tlast,
    input [7:0] target_tx_tdata,

    output target_rx_tvalid,
    input target_rx_tready,
    output target_rx_tlast,
    output [7:0] target_rx_tdata
);

  // -- Signals & State -- //

  reg SCK_q;
  wire SCK_en, SCK_w, SCK_x;
  wire SSEL_w, MOSI_w, MISO_w;

  wire tvalid, tready, tlast, rvalid, rready, rlast, rkeep;
  wire [7:0] tdata, rdata;

  wire yvalid, yready, ylast, xvalid, xready, xlast;
  wire [7:0] ydata, xdata;

  reg pvalid;
  reg [7:0] pdata;
  wire svalid, skeep, slast;
  wire [7:0] sdata;

  assign SCK_x  = SCK_en ? SCK_w : SPI_CPOL;

  assign rvalid = rkeep | rlast;
  assign rlast  = rcycle & ~rsck2;

  // Preload contents for the SPI target core, if FIFO is empty //
  assign svalid = rvalid | pvalid;
  assign skeep  = rkeep | pvalid;
  assign slast  = rvalid ? rlast : 1'b0;
  assign sdata  = rvalid ? rdata : pdata;


  // Register the previous value of 'SCK_en' so that it can be used to generate
  // a 'tlast' signal.
  always @(posedge SCK) begin
    SCK_q <= SCK_en;
    rsck0 <= SCK_q & ~SCK_en;
  end

  reg rsck0, rsck1, rsck2, rcycle;

  always @(posedge clock) begin
    {rsck2, rsck1} <= {rsck1, rsck0};

    if (reset) begin
      rcycle <= 1'b0;
    end else if (!rcycle && rsck2) begin
      rcycle <= 1'b1;
    end else if (rcycle && rlast) begin
      rcycle <= 1'b0;
    end
  end

  always @(posedge clock) begin
    if (reset || xvalid || pvalid) begin
      pvalid <= 1'b0;
      pdata  <= 'bx;
    end else begin
      pvalid <= 1'b1;
`ifdef __icarus
      pdata <= $urandom;
`else
      pdata <= {1'b0, HEADER};
`endif
    end
  end


  //
  //  SPI Master
  ///
  axis_afifo #(
      .WIDTH(8),
      .ABITS(4)
  ) U_TX_FIFO1 (
      .s_aresetn(~reset),

      .s_aclk(clock),
      .s_tvalid_i(master_tx_tvalid),
      .s_tready_o(master_tx_tready),
      .s_tlast_i(master_tx_tlast),
      .s_tdata_i(master_tx_tdata),

      .m_aclk    (SCK),
      .m_tvalid_o(tvalid),
      .m_tready_i(tready),
      .m_tlast_o (tlast),
      .m_tdata_o (tdata)
  );

  axis_afifo #(
      .WIDTH(8),
      .ABITS(4)
  ) U_RX_FIFO1 (
      .s_aresetn(~reset),

      .s_aclk(SCK),
      .s_tvalid_i(yvalid),
      .s_tready_o(yready),
      .s_tlast_i(ylast),
      .s_tdata_i(ydata),

      .m_aclk    (clock),
      .m_tvalid_o(master_rx_tvalid),
      .m_tready_i(master_rx_tready),
      .m_tlast_o (master_rx_tlast),
      .m_tdata_o (master_rx_tdata)
  );

  spi_master #(
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_SPI_MASTER1 (
      .clock(SCK),
      .reset(reset),

      .SCK(SCK_w),
      .SCK_en(SCK_en),
      .SSEL(SSEL_w),
      .MOSI(MOSI_w),
      .MISO(MISO_w),

      .s_tvalid(tvalid),
      .s_tready(tready),
      .s_tlast (tlast),
      .s_tdata (tdata),

      .m_tvalid(yvalid),
      .m_tready(yready),
      .m_tlast (ylast),
      .m_tdata (ydata)
  );


  //
  //  SPI Target
  ///
  spi_target #(
      .HEADER(7'h23),
      .WIDTH (8)
  ) U_SPI_TARGET1 (
      .clock(clock),
      .reset(reset),

      .status_i  (7'hx),
      .overflow_o(overflow_o),
      .underrun_o(underrun_o),

                   // todo: handle 1st-byte ...
      .s_tvalid(target_tx_tvalid),
      .s_tready(target_tx_tready),
      .s_tlast (target_tx_tlast),
      .s_tdata (target_tx_tdata),

      .m_tvalid(xvalid),
      .m_tready(xready),
      .m_tdata (xdata),

      .SCK_pin(SCK_x),
      .SSEL(SSEL_w),
      .MOSI(MOSI_w),
      .MISO(MISO_w)
  );

  axis_clean #(
      .WIDTH(8),
      .DEPTH(4)
  ) U_AXIS_CLEAN1 (
      .clock(clock),
      .reset(reset),

      .m_tvalid(target_rx_tvalid),
      .m_tready(target_rx_tready),
      .m_tlast (target_rx_tlast),
      .m_tkeep (),
      .m_tdata (target_rx_tdata),

      .s_tvalid(xvalid),
      .s_tready(xready),
      .s_tlast (1'b0),
      .s_tkeep (xvalid),
      .s_tdata (xdata)
  );


endmodule  // spi_to_spi
