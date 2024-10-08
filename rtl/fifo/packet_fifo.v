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
    localparam AZERO = {ADDRS{1'b0}},

    // Generate save/next signals using 'tlast's?
    parameter STORE_LASTS = 1,

    parameter SAVE_ON_LAST = 1,  // Generate a 'save' strobe on 'tlast'?
    parameter LAST_ON_SAVE = 0,  // Todo: Generate a 'tlast' strobe on 'save'?
    parameter NEXT_ON_LAST = 1,  // Advance to 'next' packet on 'tlast'?

    // Break up large packets into chunks of up to this length? If we reach the
    // maximum packet-length, de-assert 'tready', and wait for a 'save_i'.
    parameter USE_LENGTH = 0,  // Todo
    parameter MAX_LENGTH = DEPTH / 2,
    localparam MAX_LIMIT = MAX_LENGTH - 1,

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
  reg save_q, drop_q;
  wire fetch_w, store_w, match_w, chunk_w, frame_w, wfull_w, empty_w;
  wire reject_a, accept_a, finish_a, replay_a;
  wire [ABITS:0] level_w, wdiff, rdiff;
  wire [ASB:0] wsize, rsize;

  // Optional extra stage of registers, so that block SRAMs can be used.
  reg xvalid, xlast;
  wire xready, rstop_w;
  reg [MSB:0] xdata;

  assign s_tready = wready;
  assign level_o  = level_q;

  // -- FIFO Status Signals -- //

  wire save_w = ((SAVE_ON_LAST && s_tvalid && wready && s_tlast) || save_i) && !drop_i;

  wire wrfull_next = waddr_next[ASB:0] == raddr[ASB:0] && store_w && !fetch_w;
  wire wrfull_curr = match_w && waddr[ABITS] != raddr[ABITS] && fetch_w == store_w;

  wire rempty_next = raddr_next[ASB:0] == paddr[ASB:0] && fetch_w && !accept_a;
  wire rempty_curr = paddr == raddr && fetch_w == accept_a;


  // Accept/reject a packet-store
  assign accept_a = LAST_ON_SAVE ? save_q : save_w;
  assign reject_a = drop_i;

  // Advance/replace a packet-fetch
  assign finish_a = ((NEXT_ON_LAST && m_tvalid && m_tready && m_tlast) || next_i) && !redo_i;
  assign replay_a = redo_i;

  // SRAM control & status signals
  assign match_w = waddr[ASB:0] == raddr[ASB:0];
  assign wfull_w = wrfull_curr || wrfull_next;
  assign empty_w = rempty_curr || rempty_next;

  // -- Packet-Length and Framing -- //

  assign wdiff = waddr_next - paddr;
  assign wsize = wdiff[ASB:0];

  assign rdiff = raddr_next - rplay;
  assign rsize = rdiff[ASB:0];

  assign chunk_w = USE_LENGTH && wsize == MAX_LIMIT;
  assign frame_w = USE_LENGTH && rsize == MAX_LIMIT;

  // -- Write Port -- //

  generate
    if (LAST_ON_SAVE) begin : g_last_on_save

      // Extra layer of registers, so that we can generate 'tlast' signals on
      // 'save', while also supporting 'tkeep'. This is because 'save' may
      // arrive when 'tvalid' is LO, or when 'tkeep' is LO, or there may not be
      // a 'tlast', to trigger 'store_w' and 'accept_a'.

      reg xvld, xlst, xmax;
      reg [7:0] xdat;

      assign store_w = xvld && wready && (s_tvalid && s_tkeep || xlst && SAVE_ON_LAST || save_q);
      assign last_w  = xlst || save_q && LAST_ON_SAVE || xmax;
      assign data_w  = xdat;
      assign level_w = waddr_next[ASB:0] - raddr_next[ASB:0] + ((capture_a | xvld) & ~release_a);

      wire capture_a = s_tvalid && wready && s_tkeep;
      wire release_a = xvld && (xlst && SAVE_ON_LAST || save_q);

      always @(posedge clock) begin
        if (reset) begin
          save_q <= 1'b0;
          drop_q <= 1'b0;
          xvld   <= 1'b0;
          xlst   <= 1'b0;
          xmax   <= 1'b0;
          xdat   <= {WIDTH{1'bx}};
        end else begin
          save_q <= save_w;
          drop_q <= drop_i;

          if (capture_a) begin
            // Data captured, and we maintain one transfer outside of the FIFO,
            // until either 'tlast' (and 'SAVE_ON_LAST) or 'save' asserts.
            xvld <= 1'b1;
            xlst <= s_tlast || LAST_ON_SAVE && save_i || SAVE_ON_LAST && chunk_w;
            xmax <= chunk_w;
            xdat <= s_tdata;
          end else if (release_a || drop_i) begin
            // Data stored to SRAM, but no new data arrived, this cycle.
            xvld <= 1'b0;
            xlst <= 1'b0;
            xmax <= 1'b0;
            xdat <= {WIDTH{1'bx}};
          end
        end
      end

    end else begin : g_normal_save

      assign store_w = s_tvalid && wready && s_tkeep;
      assign last_w  = s_tlast || chunk_w;
      assign data_w  = s_tdata;
      assign level_w = waddr_next[ASB:0] - raddr_next[ASB:0];

    end
  endgenerate

  wire waddr_of_w;
  assign {waddr_of_w, waddr_next} = store_w ? waddr + 1 : {1'b0, waddr};

  always @(posedge clock) begin
    if (reset) begin
      waddr  <= AZERO;
      wready <= 1'b0;
    end else begin
      wready <= ~wfull_w;

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

  // -- Packet/Frame Pointers -- //

  reg [ABITS:0] rprev;

  always @(posedge clock) begin
    if (reset) begin
      paddr <= AZERO;
      rplay <= AZERO;
    end else begin
      if (accept_a) begin
        paddr <= waddr_next;
      end

      if (finish_a) begin
        rplay <= rprev;
      end
    end
  end


  // -- Read Port -- //

  wire raddr_of_w;
  assign {raddr_of_w, raddr_next} = fetch_w ? raddr + 1 : {1'b0, raddr};

  always @(posedge clock) begin
    if (reset) begin
      raddr  <= AZERO;
      rprev  <= AZERO;
      rvalid <= 1'b0;
    end else begin
      rvalid <= ~empty_w;

      if (replay_a) begin
        raddr <= rplay;
      end else begin
        raddr <= raddr_next;
        rprev <= rstop_w ? raddr : rprev;
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

      wire rlast_w;
      wire [MSB:0] rdata_w;

      assign {rlast_w, rdata_w} = STORE_LASTS != 0 ? sram[raddr[ASB:0]] : {1'b0, sram[raddr[ASB:0]]};

      // Suitable for Xilinx Distributed SRAM's, and similar, with fast, async
      // reads.
      assign fetch_w = rvalid && m_tready;
      assign rstop_w = rvalid && rlast_w && m_tready;

      assign m_tvalid = rvalid;
      assign m_tlast = rlast_w;
      assign m_tdata = rdata_w;

    end // g_async
  else if (OUTREG > 0) begin : g_outregs

      assign fetch_w = rvalid && (xvalid && xready || !xvalid);
      assign rstop_w = xvalid && xlast && xready;

      always @(posedge clock) begin
        if (reset || replay_a) begin
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
          .reset(reset || replay_a),

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
