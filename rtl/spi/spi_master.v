`timescale 1ns / 100ps
/**
 * Module      : rtl/spi/spi_master.v
 * Copyright   : (C) Patrick Suggate 2024
 * License     : MIT
 * 
 * Maintainer  : Patrick Suggate <patrick.suggate@gmail.com>
 * Stability   : Experimental
 * Portability : only tested with GoWin GW2A
 * 
 * Synchronous SPI master.
 * 
 * Note: This file is part of TART.
 */
module spi_master #(
    parameter SPI_CPOL = 0,
    parameter SPI_CPHA = 0
) (
    input clock,
    input reset,

    output SCK_en,
    output SSEL,
    output MOSI,
    input  MISO,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [7:0] m_tdata,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input s_tkeep,
    input [7:0] s_tdata
);

  // -- Constants -- //

  localparam [3:0] ST_IDLE = 4'h1, ST_BUSY = 4'h2, ST_LAST = 4'h4, ST_DONE = 4'h8;


  // -- Signals & State -- //

  reg clken;
  reg [3:0] state, snext;
  reg [2:0] count;
  reg [7:0] tdata, rdata, tnext, rnext;
  wire [3:0] cnext;


  // -- Signal and I/O Assignments -- //

  assign SCK_en = clken;
  assign SSEL   = state != ST_IDLE;
  assign MOSI   = tdata[7];

  assign cnext  = count + 3'd1;


  // -- FSM Combinational Logic -- //

  always @* begin
    snext = state;
    tnext = tdata;
    rnext = rdata;

    if (s_tvalid && s_tkeep) begin
      snext = ST_BUSY;
    end else if (cnext[3] && s_tvalid && s_tlast) begin
      snext = ST_DONE;
    end else if (cnext[3] && !s_tvalid) begin
      snext = ST_IDLE;
    end

    if (snext == ST_BUSY) begin
      tnext <= cnext[3] ? s_tdata : {tdata[6:0], 1'bx};
      rnext <= {rdata[6:0], MISO};
    end
  end


  // -- SPI Master FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;

      clken <= 1'b0;
      count <= 3'd0;

      tdata <= 8'bx;
      rdata <= 8'bx;
    end else begin
      state <= snext;

      clken <= snext != ST_IDLE;
      count <= cnext[2:0];

      tdata <= state == ST_IDLE ? s_tdata : tnext;
      rdata <= rnext;
    end
  end


endmodule  // spi_master
