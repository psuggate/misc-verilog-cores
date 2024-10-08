`timescale 1ns / 100ps
/**
 * Synchronous FIFO with similar flow-control to that used by AXI-Stream.
 *
 * Various FPGA SRAM-types can be supported, with either zero or one pipeline-
 * registers (within the SRAM primitive), with additional pipeline registers, as
 * well as supporting fast-reads (similar to First-Word-Fall-Through, FWFT), if
 * desired.
 *
 * There are four output pipeline settings, with the last two instantiating a
 * skid-buffer, for the output data, so that registered-output SRAM's can be
 * used; e.g., Xilinx Block SRAMs, or GoWin BSRAMs, and without additional wait-
 * states when stopping and starting.
 *
 * Notes:
 *  - OUTREG = 0 for a FIFO that supports LUT-SRAMs with asynchronous reads
 *  - OUTREG = 1 for the smallest block-SRAM FIFO
 *  - OUTREG = 2 for a block-SRAM FIFO with First-Word Fall-Through (FWFT)
 *  - OUTREG = 3 for a block-SRAM, FWFT FIFO with "double-fall-through"
 */
module sync_fifo #(
    parameter OUTREG = 1,  // 0, 1, 2, or 3

    parameter  WIDTH = 8,
    localparam MSB   = WIDTH - 1,

    parameter  ABITS = 4,
    localparam DEPTH = 1 << ABITS,
    localparam ASB   = ABITS - 1,
    localparam ADDRS = ABITS + 1,
    localparam AZERO = {ABITS{1'b0}}
) (
    input clock,
    input reset,

    output [ASB:0] level_o,

    input valid_i,
    output ready_o,
    input [MSB:0] data_i,

    output valid_o,
    input ready_i,
    output [MSB:0] data_o
);

  reg [MSB:0] sram[0:DEPTH-1];

  // Read- & write- port signals
  reg wready, rvalid;
  reg [ABITS:0] waddr, raddr;
  wire waddr_of_w, raddr_of_w;
  wire [ABITS:0] waddr_w, raddr_w, waddr_next, raddr_next;

  // Transition signals
  reg [ASB:0] level_q;
  wire fetch_w, store_w, match_w, wfull_w, empty_w;

  // Optional extra stage of registers, so that block SRAMs can be used
  reg xvalid;
  reg [MSB:0] xdata;
  wire xready_w, svalid_w, tvalid_w, noreg_w;
  wire sready, tready;
  wire [MSB:0] sdata_w;

  assign level_o = level_q;
  assign ready_o = wready;

  // -- FIFO Status Signals -- //

  wire wrfull_next, wrfull_curr, rempty_next, rempty_curr;
  wire incr_w, decr_w;
  wire [ABITS:0] lnext_w;

  assign wrfull_next = waddr_next[ASB:0] == raddr[ASB:0] && store_w && !fetch_w;
  assign wrfull_curr = match_w && waddr[ABITS] != raddr[ABITS] && fetch_w == store_w;

  assign rempty_next = raddr_next[ASB:0] == waddr[ASB:0] && fetch_w && !store_w;
  assign rempty_curr = match_w && waddr[ABITS] == raddr[ABITS] && fetch_w == store_w;

  assign match_w = waddr[ASB:0] == raddr[ASB:0];
  assign wfull_w = wrfull_curr | wrfull_next;
  assign empty_w = rempty_curr | rempty_next;

  // Todo: is this efficient enough !?
  assign incr_w = valid_i && wready;
  assign decr_w = valid_o && ready_i;
  assign lnext_w = level_q + incr_w - decr_w;

  always @(posedge clock) begin
    if (reset) begin
      level_q <= AZERO;
    end else begin
      level_q <= lnext_w[ASB:0];
    end
  end

  // -- Read- & Write- Port Logic -- //

  assign waddr_w = store_w ? waddr_next : waddr;
  assign raddr_w = fetch_w ? raddr_next : raddr;

  assign {waddr_of_w, waddr_next} = waddr + 1;
  assign {raddr_of_w, raddr_next} = raddr + 1;

  always @(posedge clock) begin
    if (reset) begin
      waddr  <= {ADDRS{1'b0}};
      raddr  <= {ADDRS{1'b0}};
      wready <= 1'b0;
      rvalid <= 1'b0;
    end else begin
      wready <= ~wfull_w;
      rvalid <= ~empty_w;

      if (store_w) begin
        sram[waddr[ASB:0]] <= data_i;
        waddr <= waddr_next;
      end

      if (fetch_w) begin
        raddr <= raddr_next;
      end
    end
  end

  // -- Output Register (OPTIONAL) -- //

  generate
    if (OUTREG == 0) begin : g_async

      // Suitable for Xilinx Distributed SRAM's, and similar, with fast, async
      // reads.
      assign store_w = wready && valid_i;
      assign fetch_w = rvalid && ready_i;

      assign valid_o = rvalid;
      assign data_o  = sram[raddr[ASB:0]];

    end // g_async
  else if (OUTREG > 0) begin : g_outregs

      // If 'sready' then the skid-reg has somewhere to stick data
      // If 'xvalid' then the SRAM has latched data on its outputs

      // Where to stick 'data_i'? Has to go into the SRAM if:
      //  1) 'OUTREG < 2' because we are not allowed to bypass the SRAM;
      //  2) there is already data in the SRAM, so that new data is queued-up
      //     behind existing data (or else ordering won't be preserved);
      //  3) SRAM data is being transferred, but the temp-reg is not ready; OR,
      //  4) both the temp- and output registers are full.
      assign noreg_w  = OUTREG < 2 || rvalid || xvalid && !tready || !sready;

      /**
       * Write data into the SRAM unless there is:
       *  1) no space;
       *  2) a free skid-register;
       */
      assign store_w  = valid_i && wready && noreg_w;

      /**
       * Read from the SRAM whenever the output DFF is empty, or if there will be
       * a transfer at the next edge, and the SRAM is not empty.
       */
      assign fetch_w  = rvalid && (!xvalid || xvalid && xready_w);

      // -- First-Word Fall-Through -- //

      assign xready_w = sready;

      assign tvalid_w = !rvalid && xvalid && valid_i && wready;
      assign svalid_w = xvalid || !xvalid && !rvalid && valid_i && OUTREG > 1;
      assign sdata_w  = !xvalid && valid_i && sready && OUTREG > 1 ? data_i : xdata;

      // -- SRAM Output-Register -- //

      always @(posedge clock) begin
        if (reset) begin
          xvalid <= 1'b0;
        end else begin
          if (fetch_w) begin
            xvalid <= 1'b1;
            xdata  <= sram[raddr[ASB:0]];
          end else if (xvalid && xready_w) begin
            xvalid <= 1'b0;
          end
        end
      end

      // -- Skid Register with Loadable, Overflow Register -- //

      skid_loader #(
          .WIDTH (WIDTH),
          .BYPASS(OUTREG > 1 ? 0 : 1),
          .LOADER(OUTREG > 2 ? 1 : 0)
      ) axis_skid_inst (
          .clock(clock),
          .reset(reset),

          .s_tvalid(svalid_w),
          .s_tready(sready),
          .s_tlast (1'b0),
          .s_tdata (sdata_w),

          .t_tvalid(tvalid_w),  // If OUTREG > 2, allow the temp-register to be
          .t_tready(tready),    // explicitly loaded
          .t_tlast (1'b0),
          .t_tdata (data_i),

          .m_tvalid(valid_o),
          .m_tready(ready_i),
          .m_tlast (),
          .m_tdata (data_o)
      );

    end  // g_outregs
  endgenerate


endmodule  /* sync_fifo */
