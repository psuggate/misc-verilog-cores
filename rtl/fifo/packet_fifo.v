`timescale 1ns / 100ps
/**
 * Packet FIFO use cases:
 *  - break a "frame" into packets of 'MAX_LENGTH', and residual;
 *  - only update occupancy when 'tlast' is received/transmitted;
 *  - support 'redo' of a packet, if an ACK was not received;
 *  - 'drop' a packet on CRC failure;
 *  - removes any transfers where 'tkeep == 0';
 */
module packet_fifo #(
    parameter  WIDTH = 8,
    localparam MSB   = WIDTH - 1,

    parameter  DEPTH = 16,
    localparam ABITS = $clog2(DEPTH),
    localparam ASB   = ABITS - 1,
    localparam ADDRS = ABITS + 1,
    localparam AZERO = {ABITS{1'b0}},

    // Generate save/next signals using 'tlast's?
    parameter STORE_LASTS = 1,

    parameter SAVE_ON_LAST = 1,  // Generate a 'save' strobe on 'tlast'?
    parameter LAST_ON_SAVE = 0,  // Todo: Generate a 'tlast' strobe on 'save'?
    parameter NEXT_ON_LAST = 1,  // Advance to 'next' packet on 'tlast'?

    // Break up large packets into chunks of up to this length? If we reach the
    // maximum packet-length, de-assert 'tready', and wait for a 'save_i'.
    parameter USE_LENGTH = 0,   // Todo
    parameter MAX_LENGTH = 512,

    // Skid-buffer for the output data, so that registered-output SRAM's can be
    // used, e.g., Xilinx Block SRAMs, or GoWin BSRAMs.
    parameter OUTREG = 1  // 0, 1, or 2
) (
    input clock,
    input reset,

    output [ASB:0] level_o,

    input drop_i,
    input save_i,
    input redo_i,
    input next_i,

    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [MSB:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [MSB:0] m_tdata
);

  // Store the 'last'-bits?
  localparam integer WSB = STORE_LASTS != 0 ? WIDTH : MSB;

  reg [WSB:0] sram[0:DEPTH-1];

  // Write- & Read- port signals
  reg rvalid, wready;
  reg [ABITS:0] waddr, raddr, rplay;
  wire [ABITS:0] waddr_next, raddr_next;
  wire last_w;
  wire [MSB:0] data_w;

  // Packet address signals
  reg [ABITS:0] paddr;

  // Transition signals
  reg [ASB:0] level_q;
  wire fetch_w, store_w, match_w, chunk_w, frame_w, wfull_w, empty_w;
  wire reject_a, accept_a, finish_a, replay_a;
  wire [ABITS:0] level_w, waddr_w, raddr_w;

  // Optional extra stage of registers, so that block SRAMs can be used.
  reg xvalid, xlast;
  wire xready;
  reg [MSB:0] xdata;

  assign s_tready = wready;
  assign level_o  = level_q;

  // -- FIFO Status Signals -- //

  wire wrfull_next = waddr_next[ASB:0] == raddr[ASB:0] && store_w && !fetch_w;
  wire wrfull_curr = match_w && waddr[ABITS] != raddr[ABITS] && fetch_w == store_w;

  wire rempty_next = raddr_next[ASB:0] == paddr[ASB:0] && fetch_w && !accept_a;
  wire rempty_curr = paddr == raddr && fetch_w == accept_a;


  // Accept/reject a packet-store
  assign accept_a = ((SAVE_ON_LAST && s_tvalid && wready && s_tlast) || save_i) && !drop_i;
  assign reject_a = drop_i;  // ??

  // Advance/replace a packet-fetch
  assign finish_a = ((NEXT_ON_LAST && m_tvalid && m_tready && m_tlast) || next_i) && !redo_i;
  assign replay_a = redo_i;

  // SRAM control & status signals
  assign match_w  = waddr[ASB:0] == raddr[ASB:0];
  assign wfull_w  = wrfull_curr || wrfull_next;
  assign empty_w  = rempty_curr || rempty_next;

  assign waddr_w  = store_w ? waddr_next : waddr;
  assign raddr_w  = fetch_w ? raddr_next : raddr;

  // -- Write Port -- //

  generate
    if (LAST_ON_SAVE) begin : g_last_on_save

      // Extra layer of registers, so that we can generate 'tlast' signals on
      // 'save', while also supporting 'tkeep'. This is because 'save' may
      // arrive when 'tvalid' is LO, or when 'tkeep' is LO, or there may not be
      // a 'tlast', to trigger 'store_w' and 'accept_a'.

      reg xvld, xlst, save;
      reg [7:0] xdat;

      assign store_w = xvld && wready && (s_tvalid && s_tkeep || xlst && SAVE_ON_LAST || save);
      assign last_w  = xlst || (save && LAST_ON_SAVE);
      assign data_w  = xdat;
      assign level_w = waddr_w[ASB:0] - raddr_w[ASB:0] + xvld;

      always @(posedge clock) begin
        if (reset) begin
          save <= 1'b0;
          xvld <= 1'b0;
          xlst <= 1'b0;
          xdat <= 'bx;
        end else begin
          save <= accept_a;

          if (s_tvalid && wready && s_tkeep) begin
            // Data captured, and we maintain one transfer outside of the FIFO,
            // until either 'tlast' (and 'SAVE_ON_LAST) or 'save' asserts.
            xvld <= 1'b1;
            xlst <= s_tlast || LAST_ON_SAVE && save_i;
            xdat <= s_tdata;
          end else if (store_w) begin
            // Data stored to SRAM, but no new data arrived, this cycle.
            xvld <= 1'b0;
            xlst <= 1'b0;
            xdat <= 'bx;
          end
        end
      end

    end else begin : g_normal_save

      assign store_w = s_tvalid && wready;
      assign last_w  = s_tlast;
      assign data_w  = s_tdata;
      assign level_w = waddr_w[ASB:0] - raddr_w[ASB:0];

    end
  endgenerate

  assign waddr_next = store_w ? waddr + 1 : waddr;

  always @(posedge clock) begin
    if (reset) begin
      waddr  <= AZERO;
      wready <= 1'b0;
    end else begin
      wready <= ~wfull_w && ~chunk_w;

      if (reject_a) begin
        waddr <= paddr;
      end else begin
        if (store_w) begin
          sram[waddr[ASB:0]] <= STORE_LASTS != 0 ? {last_w, data_w} : data_w;
        end
        waddr <= waddr_next;
      end
    end
  end


  // -- Frame Pointers -- //

  wire [ABITS:0] wdiff, rdiff;
  wire [ASB:0] wsize, rsize;

  assign wdiff   = waddr_next - paddr;
  assign wsize   = wdiff[ASB:0];

  assign rdiff   = raddr_next - rplay;
  assign rsize   = rdiff[ASB:0];

  assign chunk_w = USE_LENGTH && wsize == MAX_LENGTH;
  assign frame_w = USE_LENGTH && rsize == MAX_LENGTH;

  always @(posedge clock) begin
    if (reset) begin
      paddr <= AZERO;
      rplay <= AZERO;
    end else begin
      if (accept_a) begin
        paddr <= waddr_next;
      end

      if (finish_a) begin
        rplay <= raddr_next;
      end
    end
  end


  // -- Read Port -- //

  assign raddr_next = fetch_w ? raddr + 1 : raddr;

  always @(posedge clock) begin
    if (reset) begin
      raddr  <= AZERO;
      rvalid <= 1'b0;
    end else begin
      rvalid <= ~empty_w && ~frame_w;

      if (replay_a) begin
        raddr <= rplay;
      end else begin
        raddr <= raddr_next;
      end
    end
  end


  // -- FIFO Status -- //

  always @(posedge clock) begin
    if (reset) begin
      level_q <= AZERO;
    end else begin
      level_q <= level_w[ASB:0];
    end
  end


  // -- Output Register (OPTIONAL) -- //

  generate
    if (OUTREG == 0) begin : g_async

      wire [WIDTH:0] data_w = STORE_LASTS != 0 ? sram[raddr[ASB:0]] : {1'b0, sram[raddr[ASB:0]]};

      // Suitable for Xilinx Distributed SRAM's, and similar, with fast, async
      // reads.
      assign fetch_w  = rvalid && m_tready;

      assign m_tvalid = rvalid;
      assign m_tlast  = data_w[WIDTH];
      assign m_tdata  = data_w[MSB:0];

    end // g_async
  else if (OUTREG > 0) begin : g_outregs

      assign fetch_w = rvalid && (xvalid && xready || !xvalid);

      always @(posedge clock) begin
        if (reset) begin
          xvalid <= 1'b0;
        end else begin
          if (fetch_w) begin
            xvalid <= 1'b1;
            {xlast, xdata} <= STORE_LASTS != 0 ? sram[raddr[ASB:0]] : {1'b0, sram[raddr[ASB:0]]};
          end else if (xvalid && xready) begin
            xvalid <= 1'b0;
          end
        end
      end

      axis_skid #(
          .WIDTH (WIDTH),
          .BYPASS(OUTREG > 1 ? 0 : 1)
      ) axis_skid_inst (
          .clock(clock),
          .reset(reset),

          .s_tvalid(xvalid),
          .s_tready(xready),
          .s_tlast (xlast),
          .s_tdata (xdata),

          .m_tvalid(m_tvalid),
          .m_tready(m_tready),
          .m_tlast (m_tlast),
          .m_tdata (m_tdata)
      );

    end  // g_outregs
  endgenerate


endmodule  /* packet_fifo */
