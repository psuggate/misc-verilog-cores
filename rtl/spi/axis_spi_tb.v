`timescale 1ns / 100ps
/**
 * Testbench for the SPI master & target cores, for transmitting and receiving
 * packets via AXI4-Stream interconnect.
 */
module axis_spi_tb;

  parameter [7:0] HEADER = 8'ha7;
  parameter integer SPI_CPOL = 0;
  parameter integer SPI_CPHA = 0;

  parameter integer WIDTH = 8;
  localparam integer MSB = WIDTH - 1;

  parameter integer ABITS = 16;
  localparam integer ASB = ABITS - 1;

  initial begin
    $display("SPI Slave & Master AXI cores:");
    $display(" - SPI clock-polarity: %1d", SPI_CPOL);
    $display(" - SPI clock-phase:    %1d", SPI_CPHA);
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("axis_spi_tb.vcd");
    $dumpvars;

    #1500 $finish;  // todo ...
  end


  // -- Signals & State -- //

  reg clock = 1, reset, SCK = 1;
  wire SCK_en;
  wire SCK_w, SCK_p, SSEL, MOSI, MISO;

  assign SCK_p = SCK_en ? SCK_w : SPI_CPOL;

  always #5 clock <= ~clock;
  always #10 SCK <= ~SCK;

  initial begin
    #10 reset <= 1'b1;
    #20 reset <= 1'b0;
  end

  wire overflow, underrun;

  // AXIS Write Signals //
  reg tvalid_q, tlast_q, tkeep_q;
  wire tready_w;
  reg [7:0] tdata_q;

  // AXIS Read Signals //
  reg rready_q;
  wire rvalid_w, rlast_w, rkeep_w;
  wire [7:0] rdata_w;


  always @(posedge clock) begin
    if (reset) begin
      tvalid_q <= 1'b0;
      tlast_q  <= 1'b0;
      tkeep_q  <= 1'b0;
      rready_q <= 1'b0;
    end
  end


  //
  // Cores Under New Tests
  ///
  axis_spi_master #(
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_AXIS_SPI_MASTER1 (
      .clock(clock),
      .reset(reset),
      .ARSTn(reset),

      .s_tvalid(1'b0),
      .s_tready(),
      .s_tkeep (1'b0),
      .s_tlast (1'b0),
      .s_tdata (8'hx),

      .m_tvalid(),
      .m_tready(1'b0),
      .m_tkeep (),
      .m_tlast (),
      .m_tdata (),

      .SCK_en(SCK_en),
      .SCK(SCK_w),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );

  axis_spi_slave #(
      .WIDTH(WIDTH),
      .HEADER(HEADER),
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_AXIS_SPI_TARGET1 (
      .clock(clock),
      .reset(reset),

      .status_i  (7'h7f),
      .overflow_o(overflow),
      .underrun_o(underrun),

      .m_tvalid_o(rvalid_w),
      .m_tready_i(rready_q),
      .m_tlast_o (rlast_w),
      .m_tkeep_o (rkeep_w),
      .m_tdata_o (rdata_w),

      .s_tvalid_i(tvalid_q),
      .s_tready_o(tready_w),
      .s_tlast_i (tlast_q),
      .s_tkeep_i (tkeep_q),
      .s_tdata_i (tdata_q),

      .SCK (SCK_p),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );


endmodule  // axis_spi_tb
