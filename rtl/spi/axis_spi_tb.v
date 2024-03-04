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

  assign SCK_p = SCK_en ? SCK : SPI_CPOL;

  always #5 clock <= ~clock;
  always #10 SCK <= ~SCK;

  initial begin
    #10 reset <= 1'b1;
    #20 reset <= 1'b0;
  end


  // -- Simulation Signals & State -- //

  reg svalid, slast, skeep, mready;
  reg rready, tvalid, tlast, tkeep;
  reg [7:0] sdata, tdata;
  wire tready, rvalid, rkeep;
  wire sready, mvalid, mlast, mkeep;
  wire [7:0] mdata, rdata;

  wire overflow, underrun;


  // -- Simulation Stimulus -- //

  initial begin : I_STIMULATE
    #60 axis_send(4);
  end

  initial sdata <= $urandom;

  always @(posedge clock) begin
    if (reset) begin
      svalid <= 1'b0;
      slast  <= 1'b0;
      skeep  <= 1'b0;
      mready <= 1'b0;

      tvalid <= 1'b0;
      tlast  <= 1'b0;
      tkeep  <= 1'b0;
      rready <= 1'b0;
    end else begin
      if (svalid && !tvalid) begin
        tvalid <= 1'b1;
        tlast  <= slast;
        tkeep  <= 1'b1;
        tdata  <= $urandom;
      end else if (tvalid && tready && !tlast) begin
        tlast <= slast;
        tdata <= $urandom;
      end else if (tvalid && tready && tlast) begin
        tvalid <= 1'b0;
        tlast  <= 1'b0;
        tkeep  <= 1'b0;
      end
    end
  end


  // -- Perform write transfer (128-bit) -- //

  task axis_send;
    input [7:0] len;
    begin
      integer scount, rcount;
      reg done;

      scount <= len;
      rcount <= len;
      done   <= 1'b0;

      svalid <= 1'b1;
      slast  <= len == 8'd0;
      skeep  <= 1'b1;
      sdata  <= $urandom;
      mready <= 1'b1;
      rready <= 1'b1;
      @(posedge clock);

      while (!done) begin
        @(posedge clock);

        if (svalid && sready) begin
          scount <= scount != 8'd0 ? scount - 1 : scount;
          svalid <= scount != 8'd0;
          slast  <= scount == 8'd1;
          sdata  <= scount != 8'd0 ? $urandom : sdata;
        end

        if (rvalid && rready) begin
          rcount <= rcount - 1;
          rready <= rcount != 8'd0;
        end

        done <= rvalid & rready;
      end
      @(posedge clock);

      svalid <= 1'b0;
      skeep  <= 1'b0;
      slast  <= 1'b0;
      mready <= 1'b0;
      rready <= 1'b0;
      @(posedge clock);

      $display("%10t: TX done", $time);
    end
  endtask  // axis_send


  //
  // Cores Under New Tests
  ///
  axis_spi_master #(
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_AXIS_SPI_MASTER1 (
      .clock(clock),
      .reset(reset),
      .ARSTn(~reset),

      .s_tvalid(svalid),
      .s_tready(sready),
      .s_tlast (slast),
      .s_tdata (sdata),

      .m_tvalid(mvalid),
      .m_tready(mready),
      .m_tlast (mlast),
      .m_tdata (mdata),

      .SCK_en(SCK_en),
      .SCK(SCK),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );

  axis_spi_target #(
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

      .m_tvalid_o(rvalid),
      .m_tready_i(rready),
      .m_tdata_o (rdata),

      .s_tvalid_i(tvalid),
      .s_tready_o(tready),
      .s_tlast_i (tlast),
      .s_tdata_i (tdata),

      .SCK (SCK_p),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );


  //
  //  SPI-to-SPI loopback core tests
  ///
  wire qvalid, qready, qlast;
  wire [7:0] qdata;

  spi_to_spi #(
      .SPI_CPOL(SPI_CPOL),
      .SPI_CPHA(SPI_CPHA)
  ) U_SPI_TO_SPI1 (
      .clock(clock),
      .reset(reset),
      .SCK  (SCK),

      .overflow_o(),
      .underrun_o(),

      .m_tvalid(qvalid),
      .m_tready(1'b1),
      .m_tlast (qlast),
      .m_tdata (qdata),

      .s_tvalid(svalid),
      .s_tready(qready),
      .s_tlast (slast),
      .s_tdata (sdata)
  );


endmodule  // axis_spi_tb
