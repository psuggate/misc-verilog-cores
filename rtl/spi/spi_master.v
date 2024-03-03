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

    output SCK,
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
    input [7:0] s_tdata
);

  // -- Constants -- //

  localparam [4:0] ST_IDLE = 5'h01, ST_SSEL = 5'h02, ST_BUSY = 5'h04, ST_LAST = 5'h08, ST_DONE = 5'h10;


  // -- Signals & State -- //

  reg clken, ready, valid, last;
  reg [4:0] state, snext;
  reg [2:0] count;
  reg [7:0] tdata, rdata, tnext, rnext;
  wire [3:0] cnext;


  // -- Signal and I/O Assignments -- //

  assign s_tready = ready;
  assign m_tvalid = valid;
  assign m_tlast = last;
  assign m_tdata = rdata;

  assign SCK = SPI_CPOL ? ~clock : clock;
  assign SCK_en = clken;
  assign SSEL = state == ST_IDLE;
  assign MOSI = tdata[7];

  assign cnext = count + 3'd1;


  // -- FSM Combinational Logic -- //

  always @* begin
    snext = state;
    tnext = tdata;
    rnext = rdata;

    case (state)
      ST_IDLE: begin
        snext = s_tvalid ? ST_SSEL : state;
        tnext = s_tvalid ? s_tdata : tdata;
        rnext = 'bx;  // {rdata[6:0], MISO};
      end
      ST_SSEL: begin
        // Assert chip-select prior to starting SCK
        snext = cnext[3] ? ST_BUSY : state;
        tnext = tdata;
        rnext = {rdata[6:0], MISO};
      end
      ST_BUSY: begin
        if (cnext[3]) begin
          snext = s_tvalid ? (s_tlast ? ST_LAST : state) : ST_DONE;
          tnext = s_tdata;
        end else begin
          snext = state;
          tnext = {tdata[6:0], 1'bx};
        end
        rnext = {rdata[6:0], MISO};
      end
      ST_LAST: begin
        snext = cnext[3] ? ST_DONE : state;
        tnext = {tdata[6:0], 1'bx};
        rnext = {rdata[6:0], MISO};
      end
      // default: begin
      ST_DONE: begin
        snext = ST_IDLE;
      end
    endcase
  end


  // -- SPI Master FSM -- //

  always @(negedge clock) begin
    if (reset || state == ST_DONE) begin
      clken <= 1'b0;
    end else if (state == ST_BUSY) begin
      clken <= 1'b1;
    end
  end

  generate
    if (SPI_CPHA == 0) begin : g_cpha0

      // Note: If 'CPOL==1' then this is still correct, as we're using 'clock', not
      //   'SCK'.
      always @(posedge clock) begin
        if (reset) begin
          state <= ST_IDLE;
          count <= 3'd0;

          ready <= 1'b0;
          valid <= 1'b0;
          last  <= 1'b0;

          tdata <= 8'bx;
          rdata <= 8'bx;
        end else begin
          state <= snext;
          count <= snext != ST_IDLE ? cnext[2:0] : 3'd0;

          ready <= state == ST_IDLE || clken && cnext[3];
          valid <= clken && cnext[3];
          last  <= clken && cnext[3] && snext == ST_IDLE;

          tdata <= tnext;
          rdata <= rnext;
        end
      end

    end else begin : g_cpha1

      // Note: If 'CPOL==1' then this is still correct, as we're using 'clock', not
      //   'SCK'.
      // Todo: use an extra set of output registers !?
      always @(negedge clock) begin
        if (reset) begin
          state <= ST_IDLE;
          count <= 3'd0;

          ready <= 1'b0;
          valid <= 1'b0;
          last  <= 1'b0;

          tdata <= 8'bx;
          rdata <= 8'bx;
        end else begin
          state <= snext;
          count <= snext != ST_IDLE ? cnext[2:0] : 3'd0;

          ready <= state == ST_IDLE || clken && cnext[3];
          valid <= clken && cnext[3];
          last  <= clken && cnext[3] && snext == ST_IDLE;

          tdata <= tnext;
          rdata <= rnext;
        end
      end

    end
  endgenerate


  // -- Simulation Only -- //

`ifdef __icarus

  wire dbg_cnext = cnext[3];
  reg [39:0] dbg_state, dbg_snext;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_SSEL: dbg_state = "SSEL";
      ST_BUSY: dbg_state = "BUSY";
      ST_LAST: dbg_state = "LAST";
      ST_DONE: dbg_state = "DONE";
      default: dbg_state = "XXXX";
    endcase
  end

  always @* begin
    case (snext)
      ST_IDLE: dbg_snext = "IDLE";
      ST_SSEL: dbg_snext = "SSEL";
      ST_BUSY: dbg_snext = "BUSY";
      ST_LAST: dbg_snext = "LAST";
      ST_DONE: dbg_snext = "DONE";
      default: dbg_snext = "XXXX";
    endcase
  end

`endif


endmodule  // spi_master
