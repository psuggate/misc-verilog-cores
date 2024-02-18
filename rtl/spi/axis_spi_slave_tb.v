`timescale 1ns / 100ps
module axis_spi_slave_tb;

  parameter [7:0] HEADER = 8'ha7;
  parameter integer WIDTH = 8;
  parameter integer SPI_CPOL = 0;
  parameter integer SPI_CPHA = 0;

  initial begin
    $display("SPI Slave to AXI core:");
    $display(" - SPI clock-polarity: %1d", SPI_CPOL);
    $display(" - SPI clock-phase:    %1d", SPI_CPHA);
  end


  // -- Simulation Data -- //

  initial begin
    $dumpfile("axis_spi_slave_tb.vcd");
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


  //
  // Cores Under New Tests
  ///
  axis_spi_slave #(
      .HEADER_BYTE(HEADER),
      .WIDTH(WIDTH),
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_AXIS_SPI1 (
      .clock(clock),
      .reset(reset),
      .SCK  (SCK),
      .SSEL (SSEL),
      .MOSI (MOSI),
      .MISO (MISO)
  );


endmodule  // axis_spi_slave_tb
