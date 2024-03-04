`timescale 1ns / 100ps
module spi_to_spi #(
    parameter SPI_CPOL = 0,
    parameter SPI_CPHA = 0
) (
    input clock,
    input reset,
    input SCK,

    output overflow_o,
    output underrun_o,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [7:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [7:0] m_tdata
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
  // assign rlast  = SCK_q & ~SCK_en;
  assign rlast = rcycle & ~rsck2;

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
      pdata  <= $urandom;
    end
  end


  axis_afifo #(
      .WIDTH(8),
      .ABITS(4)
  ) U_TX_FIFO1 (
      .s_aresetn(~reset),

      .s_aclk(clock),
      .s_tvalid_i(s_tvalid),
      .s_tready_o(s_tready),
      .s_tlast_i(s_tlast),
      .s_tdata_i(s_tdata),

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
      .m_tvalid_o(m_tvalid),
      .m_tready_i(m_tready),
      .m_tlast_o (m_tlast),
      .m_tdata_o (m_tdata)
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

  spi_target #(
      .HEADER(7'h23),
      .WIDTH (8)
  ) U_SPI_TARGET1 (
      .clock(clock),
      .reset(reset),

      .status_i  (7'hx),
      .overflow_o(overflow_o),
      .underrun_o(underrun_o),

      .s_tvalid(xvalid),
      .s_tready(xready),
      .s_tlast (xlast),
      .s_tdata (xdata),

      .m_tvalid(rkeep),
      .m_tready(rready),
      .m_tdata (rdata),

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

      .s_tvalid(svalid),
      .s_tready(rready),
      .s_tlast (slast),
      .s_tkeep (skeep),
      .s_tdata (sdata),

      .m_tvalid(xvalid),
      .m_tready(xready),
      .m_tlast (xlast),
      .m_tkeep (),
      .m_tdata (xdata)
  );


endmodule  // spi_to_spi
