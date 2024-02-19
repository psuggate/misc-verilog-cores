`timescale 1ns / 100ps
/**
 * AXI layer over the AXI4-Stream version.
 */
module axi_spi_slave_tb;

  parameter [7:0] HEADER = 8'ha7;
  parameter integer SPI_CPOL = 0;
  parameter integer SPI_CPHA = 0;

  parameter integer WIDTH = 8;
  localparam integer MSB = WIDTH - 1;

  parameter integer ABITS = 16;
  localparam integer ASB = ABITS - 1;

  initial begin
    $display("SPI Slave to AXI core:");
    $display(" - SPI clock-polarity: %1d", SPI_CPOL);
    $display(" - SPI clock-phase:    %1d", SPI_CPHA);
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("axi_spi_slave_tb.vcd");
    $dumpvars;

    #1500 $finish;  // todo ...
  end


  // -- Signals & State -- //

  reg SCK, clock, reset;
  wire SSEL, MOSI, MISO;

  always #5 clock <= ~clock;
  always #10 SCK <= ~SCK;

  initial begin
    #10 reset <= 1'b1;
    #20 reset <= 1'b0;
  end

  // AXI Write Signals //
  reg awready_q, wready_q, bvalid_q;
  reg [1:0] bresp_q;
  wire awvalid_w, wvalid_w, wlast_w, wstrb_w, bready_w;
  wire [  1:0] awburst_w;
  wire [  7:0] awlen_w;
  wire [MSB:0] wdata_w;
  wire [ASB:0] awaddr_w;

  // AXI Read Signals //
  reg arready_q, rvalid_q, rlast_q;
  reg [  1:0] rresp_q;
  reg [MSB:0] rdata_q;
  wire arvalid_w, rready_w;
  wire [  1:0] arburst_w;
  wire [  7:0] arlen_w;
  wire [ASB:0] araddr_w;

  wire [3:0] bid_w, arid_w, rid_w;

  assign bid_w = 4'ha;
  assign rid_w = 4'hb;


  always @(posedge clock) begin
    if (reset) begin
      awready_q <= 1'b0;
      wready_q  <= 1'b0;
      bvalid_q  <= 1'b0;
      arready_q <= 1'b0;
      rvalid_q  <= 1'b0;
      rlast_q   <= 1'bx;
      bresp_q   <= 2'bx;
      rresp_q   <= 2'bx;
    end
  end


  //
  // Cores Under New Tests
  ///
  axi_spi_slave #(
      .AXI_WIDTH (WIDTH),
      .AXI_IBITS (4),
      .SPI_HEADER(HEADER),
      .SPI_WIDTH (WIDTH),
      .SPI_CPOL  (SPI_CPOL),
      .SPI_CPHA  (SPI_CPHA)
  ) U_AXI_SPI1 (
      .clock(clock),
      .reset(reset),

      .axi_awvalid_o(awvalid_w),
      .axi_awready_i(awready_q),
      .axi_awaddr_o(awaddr_w),
      .axi_awlen_o(awlen_w),
      .axi_awburst_o(awburst_w),
      .axi_wvalid_o(wvalid_w),
      .axi_wready_i(wready_q),
      .axi_wlast_o(wlast_w),
      .axi_wstrb_o(wstrb_w),
      .axi_wdata_o(wdata_w),
      .axi_bvalid_i(bvalid_q),
      .axi_bready_o(bready_w),
      .axi_bresp_i(bresp_q),
      .axi_bid_i(bid_w),

      .axi_arvalid_o(arvalid_w),
      .axi_arready_i(arready_q),
      .axi_araddr_o(araddr_w),
      .axi_arid_o(arid_w),
      .axi_arlen_o(arlen_w),
      .axi_arburst_o(arburst_w),
      .axi_rvalid_i(rvalid_q),
      .axi_rready_o(rready_w),
      .axi_rlast_i(rlast_q),
      .axi_rresp_i(rresp_q),
      .axi_rid_i(rid_w),
      .axi_rdata_i(rdata_q),

      .SCK (SCK),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );


endmodule  // axi_spi_slave_tb
