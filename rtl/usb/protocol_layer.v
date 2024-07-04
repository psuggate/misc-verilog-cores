`timescale 1ns / 100ps
/**
 * Coordinates USB transactions across all endpoints.
 * Responsible for:
 *  - selecting relevant endpoints;
 *  - controlling the MUX that feeds the packet-encoder;
 *  - generating the timeouts, as required by the USB 2.0 spec;
 *  - halting/stalling endpoints, when necessary;
 */
module protocol_layer
 #(
   parameter ENDPOINT1 = 1,
   parameter ENDPOINT2 = 0,  // todo: ...
   // parameter [3:0] BULK_IN_EP1 = 1, // toods
   // parameter [3:0] BULK_IN_EP2 = 3, // toods
   // parameter [3:0] BULK_OUT_EP1 = 2, // sdoot
   // parameter [3:0] BULK_OUT_EP2 = 4, // sdoot
   parameter PIPELINED = 0,
   parameter USE_ULPI_TX_FIFO = 0
) (
   input clock,
   input reset,

   // Configured device address (or all zero)
   input set_conf_i, // Enables end-points
   input clr_conf_i, // Disables end-points
   input [6:0] usb_addr_i, // Configured address

   // Todo: combine into status-register ??
   output usb_timeout_error_o,
   output usb_device_idle_o,
   output [2:0] err_code_o,
   output [3:0] usb_state_o,
   output [7:0] blk_state_o,
   output parity0_o,
   output parity1_o,
   output parity2_o,

   // Control end-point
   output ep0_select_o,
   output ep0_enable_o,

   // Bulk end-point #1
   input ep1_rx_rdy_i,
   input ep1_tx_rdy_i,
   input ep1_halted_i,
   output ep1_enable_o,

   // Bulk end-point #1
   input ep2_rx_rdy_i,
   input ep2_tx_rdy_i,
   input ep2_halted_i,
   output ep2_enable_o,

   // Signals from the USB packet decoder (upstream)
   input tok_recv_i,
   input tok_ping_i,
   input [6:0] tok_addr_i,
   input [3:0] tok_endp_i,

   input  hsk_recv_i,
   output hsk_send_o,
   input  hsk_sent_i,

   // DATA0/1 info from the decoder, and to the encoder
   input eop_recv_i,
   input usb_recv_i,
   input usb_busy_i,
   input usb_sent_i,
   input [3:0] dec_pid_i,

   // ULPI encoder signals
   output [3:0] enc_pid_o
);

`include "usb_defs.vh"

  // -- Module Constants -- //

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam [1:0] DATA0 = 2'b00;
  localparam [1:0] DATA1 = 2'b10;

  // FSM states for BULK transfers
  localparam [7:0] BLK_IDLE = 8'h01;
  localparam [7:0] BLK_DATI_TX = 8'h02;
  localparam [7:0] BLK_DATI_ZDP = 8'h04;
  localparam [7:0] BLK_DATI_ACK = 8'h08;
  localparam [7:0] BLK_DATI_NAK = 8'h08;
  localparam [7:0] BLK_DATO_RX = 8'h10;
  localparam [7:0] BLK_DATO_ACK = 8'h20;
  localparam [7:0] BLK_DATO_NAK = 8'h20;
  localparam [7:0] BLK_DONE = 8'h40;
  localparam [7:0] BLK_DATO_ERR = 8'h80;

  // Top-level FSM states
  localparam ST_IDLE = 4'h1;
  localparam ST_CTRL = 4'h2;  // USB Control Transfer
  localparam ST_BULK = 4'h4;  // USB Bulk Transfer
  localparam ST_DUMP = 4'h8;  // ignoring xfer, or bad things happened

  // Error-codes
  localparam ER_NONE = 3'h0;
  localparam ER_BLKI = 3'h1;
  localparam ER_BLKO = 3'h2;
  localparam ER_TOKN = 3'h3;
  localparam ER_ADDR = 3'h4;
  localparam ER_ENDP = 3'h5;
  // localparam ER_CONF = 3'h6;


  // -- Module State and Signals -- //

  reg ctl_start_q, ctl_cycle_q, ctl_error_q;

  reg [7:0] ctl_rtype_q, ctl_rargs_q;
  reg [7:0] ctl_valhi_q, ctl_vallo_q;
  reg [7:0] ctl_idxhi_q, ctl_idxlo_q;
  reg [7:0] ctl_lenhi_q, ctl_lenlo_q;

  reg [2:0] err_code_q = ER_NONE;
  wire mux_tready_w;

  // State variables
  reg [2:0] xcptr;
  wire [2:0] xcnxt = xcptr + 1;
  reg [3:0] state, xctrl;
  reg [7:0] xbulk;
  reg fetch_q, store_q;

  reg [3:0] tuser_q;
  reg tzero_q, hsend_q, terr_q;

  // JK flip-flop for the DATA0/1 parity bits
  reg parity0_q, parity1_q, parity2_q;
  reg set_parity0, clr_parity0, set_parity1, clr_parity1, set_parity2, clr_parity2;
  wire parityx_w;


  // -- Input and Output Signal Assignments -- //

  assign usb_timeout_error_o = terr_q;

  assign err_code_o = err_code_q;

  assign hsk_send_o = hsend_q;

  assign blk_start_o = state == ST_BULK && xbulk == BLK_IDLE;
  assign blk_cycle_o = state == ST_BULK;
  assign blk_endpt_o = tok_endp_i;  // todo: ??
  assign blk_fetch_o = fetch_q;
  assign blk_store_o = store_q;

  assign ctl_cycle_o = ctl_cycle_q;
  assign ctl_start_o = ctl_start_q;
  assign ctl_endpt_o = tok_endp_i;  // todo: ??

  assign ctl_rtype_o = ctl_rtype_q;
  assign ctl_rargs_o = ctl_rargs_q;
  assign ctl_value_o = {ctl_valhi_q, ctl_vallo_q};
  assign ctl_index_o = {ctl_idxhi_q, ctl_idxlo_q};
  assign ctl_length_o = {ctl_lenhi_q, ctl_lenlo_q};

  // Note: not currently used
  assign ctl_tvalid_o = 1'b0;  // usb_tready_i;
  assign ctl_tlast_o = 1'b0;
  assign ctl_tdata_o = 8'h00;

  assign blk_tready_o = mux_tready_w && xbulk == BLK_DATI_TX;
  assign ctl_tready_o = mux_tready_w && xctrl == CTL_DATI_TX;

  assign usb_tready_o = xbulk == BLK_DATO_RX ? blk_tready_i : 1'b1;  // todo: ...
  assign usb_tuser_o = tuser_q;

  assign blk_tvalid_o = xbulk == BLK_DATO_RX ? usb_tvalid_i : 1'b0;
  assign blk_tlast_o = usb_tlast_i;
  assign blk_tkeep_o = usb_tkeep_i;
  assign blk_tdata_o = usb_tdata_i;

  assign usb_state_o = state;
  assign ctl_state_o = xctrl;
  assign blk_state_o = xbulk;

  assign parity0_o = parity0_q;
  assign parity1_o = parity1_q;
  assign parity2_o = parity2_q;


  // -- Monitoring & Telemetry -- //

  wire usb_idle_w;

  assign usb_idle_w = state == ST_IDLE || xctrl == CTL_DONE || xbulk == BLK_DONE;
  assign usb_device_idle_o = usb_idle_w;


  // -- Datapath from the USB Packet Decoder -- //

  reg  usb_recv_q;
  wire usb_zero_w;

  // Zero-size data transfers (typically for STATUS messages)
  assign usb_zero_w = usb_recv_q && usb_tvalid_i && !usb_tkeep_i && usb_tlast_i;

  // Delay the 'RECV' signal to align with 'tlast' (and '!tvalid'), as this
  // condition indicates that the received packet contains no data.
  always @(posedge clock) begin
    if (reset) begin
      usb_recv_q <= 1'b0;
    end else if (usb_recv_i) begin
      usb_recv_q <= 1'b1;
    end else if (usb_tvalid_i || usb_tlast_i) begin
      usb_recv_q <= 1'b0;
    end
  end


  // -- DATA0/1/2/M Logic -- //

/*
  reg [7:0] parity;

  wire epi1_ack_w = hsk_recv_i && usb_tuser_i[3:2] == HSK_ACK && xbulk == BLK_DATI_ACK;
  wire epo1_ack_w = hsk_recv_i && usb_tuser_i[3:2] == HSK_ACK && xbulk == BLK_DATI_ACK;
*/

  // todo: which is best !?
  // wire bulk_ack_w = hsk_recv_i && usb_tuser_i == {HSK_ACK, 2'b10} && xbulk == BLK_DATI_ACK;
  // wire ctrl_ack_w = hsk_recv_i && usb_tuser_i == {HSK_ACK, 2'b10} &&
  wire bulk_ack_w = hsk_recv_i && usb_tuser_i[3:2] == HSK_ACK && xbulk == BLK_DATI_ACK;
  wire ctrl_ack_w = hsk_recv_i && usb_tuser_i[3:2] == HSK_ACK &&
       (xctrl == CTL_DATI_ACK || xctrl == CTL_STATUS_ACK);

  assign parityx_w = tok_endp_i == 0 ? parity0_q :
                     tok_endp_i == ENDPOINT1[3:0] ? parity1_q :
                     tok_endp_i == ENDPOINT2[3:0] ? parity2_q :
                     // tok_endp_i == BULK_IN_EP1[3:0] ? parity1_q :
                     // tok_endp_i == BULK_OUT_EP1[3:0] ? parity2_q :
                     parity0_q;

  always @* begin
    //
    //  BULK IN endpoint #1 ('BULK_EP_IN1') DATA0/1 parity logic
    ///
    set_parity1 = 1'b0;
    clr_parity1 = 1'b0;

    if (ENDPOINT1 != 0 && tok_endp_i == ENDPOINT1[3:0]) begin
      if (usb_recv_i && xbulk == BLK_DATO_RX && parity1_q == usb_tuser_i[3]) begin
        set_parity1 = ~parity1_q;
        clr_parity1 = parity1_q;
      end else if (bulk_ack_w) begin
        set_parity1 = ~parity1_q;
        clr_parity1 = parity1_q;
      end
    end

    //
    //  BULK endpoint #2 ('ENDPOINT2') DATA0/1 parity logic
    ///
    set_parity2 = 1'b0;
    clr_parity2 = 1'b0;

    if (ENDPOINT2 != 0 && tok_endp_i == ENDPOINT2[3:0]) begin
      if (usb_recv_i && xbulk == BLK_DATO_RX && parity2_q == usb_tuser_i[3]) begin
        set_parity2 = ~parity2_q;
        clr_parity2 = parity2_q;
      end else if (bulk_ack_w) begin
        set_parity2 = ~parity2_q;
        clr_parity2 = parity2_q;
      end
    end

    //
    //  Configuration endpoint DATA0/1 parity logic
    ///
    set_parity0 = 1'b0;
    clr_parity0 = 1'b0;

    if (tok_endp_i == 0) begin
      if (tok_recv_i) begin
        if (usb_tuser_i == {TOK_SETUP, 2'b01}) begin
          set_parity0 = 1'b0;
          clr_parity0 = 1'b1;
        end else if (usb_tuser_i[3:2] == TOK_OUT && xctrl == CTL_DATI_TOK ||
                     usb_tuser_i[3:2] == TOK_IN  && xctrl == CTL_DATO_TOK
        // end else if (usb_tuser_i == {TOK_OUT, 2'b01} && xctrl == CTL_DATI_TOK ||
        //              usb_tuser_i == {TOK_IN , 2'b01} && xctrl == CTL_DATO_TOK
                     ) begin
          set_parity0 = 1'b1;
          clr_parity0 = 1'b0;
        end
      end else if (usb_recv_i) begin
        case (xctrl)
          CTL_DATO_RX: begin
            set_parity0 = ~parity0_q;
            clr_parity0 = parity0_q;
          end
          CTL_SETUP_RX: begin
            set_parity0 = 1'b1;
            clr_parity0 = 1'b0;
          end
          CTL_STATUS_RX: begin
            set_parity0 = 1'b0;
            clr_parity0 = 1'b1;
          end
          default: begin
            set_parity0 = 1'b0;
            clr_parity0 = 1'b0;
          end
        endcase
      end else if (ctrl_ack_w) begin
        set_parity0 = ~parity0_q;
        clr_parity0 = parity0_q;
      end else if (ctl_event_i) begin
        // Set the parity-bit for BULK endpoints to 'DATA0' on "configuration
        // events" (pp.242-3)
        set_parity1 = 1'b0;
        clr_parity1 = 1'b1;
        set_parity2 = 1'b0;
        clr_parity2 = 1'b1;
      end
    end
  end

  // Parity-state J/K flip-flops //
  always @(posedge clock) begin
    // Configuration endpoint DATAx parity-bit
    if (reset || clr_parity0) begin
      parity0_q <= 1'b0;
    end else if (set_parity0) begin
      parity0_q <= 1'b1;
    end

    // BULK 'ENDPOINT1' DATAx parity-bit
    if (reset || clr_parity1) begin
      parity1_q <= 1'b0;
    end else if (set_parity1) begin
      parity1_q <= 1'b1;
    end

    // BULK 'ENDPOINT2' DATAx parity-bit
    if (reset || clr_parity2) begin
      parity2_q <= 1'b0;
    end else if (set_parity2) begin
      parity2_q <= 1'b1;
    end
  end


  // -- Compute the USB Tx Packet PID -- //

  always @(posedge clock) begin
    if (reset) begin
      tuser_q <= 4'd0;
    end else if (!hsend_q && eop_recv_i) begin
      tuser_q <= {HSK_ACK, 2'b10};
    end else if (xctrl == CTL_DATO_TOK && tok_recv_i && usb_tuser_i[3:2] == TOK_IN) begin
      tuser_q <= {DATA1, 2'b11};
    end else if (xctrl == CTL_DATI_TX && ctl_tvalid_i) begin
      tuser_q <= {parityx_w ? DATA1 : DATA0, 2'b11};
    end else if (xbulk == BLK_IDLE && tok_recv_i && usb_tuser_i[3:2] == TOK_IN) begin
      tuser_q <= {parityx_w ? DATA1 : DATA0, 2'b11};
    end
  end


  // -- End-of-Packet Timer -- //

  reg [2:0] eop_rcnt, eop_tcnt;
  reg eop_tx_q;
  wire eop_rx_w = eop_rcnt == 3'd0;
  wire eop_tx_w = eop_tcnt == 3'd0;

  // TODO:
  //  - support faster EoP's by using 'RX CMD' 'LineState' changes
  //  - the USB3317 PHY appends 'RX CMD's to the end of transfers, until EOP,
  //    so use this method instead ??
  always @(posedge clock) begin
    if (reset) begin
      eop_tcnt <= 3'd0;
      eop_tx_q <= 1'b0;
    end else begin
      if (usb_sent_i) begin
        eop_tcnt <= 3'd5;
      end else if (!eop_tx_w) begin
        eop_tcnt <= eop_tcnt - 3'd1;
      end
      eop_tx_q <= eop_tcnt == 3'd1;
    end
  end


  // -- FSM to Issue Handshake Packets -- //

  always @(posedge clock) begin
    if (reset || hsk_sent_i) begin
      hsend_q <= 1'b0;
    end else if (!hsend_q && eop_recv_i) begin
      hsend_q <= 1'b1;
    end
  end


  // -- Datapath to the USB Packet Encoder (for IN Transfers) -- //

  always @(posedge clock) begin
    if (reset || usb_busy_i) begin
      tzero_q <= 1'b0;
    end else if (state == ST_CTRL) begin
      if (xctrl == CTL_DATO_TOK && tok_recv_i && usb_tuser_i[3:2] == TOK_IN) begin
        // Tx STATUS OUT (ZDP)
        tzero_q <= 1'b1;
      end else if (tzero_q && mux_tready_w) begin
        tzero_q <= 1'b0;
      end else if (xctrl == CTL_DATI_TX && ctl_tvalid_i) begin
        tzero_q <= 1'b0;
      end else begin
        tzero_q <= tzero_q;
      end
    end else if (state == ST_BULK) begin
      if (xbulk == BLK_IDLE && usb_tuser_i[3:2] == TOK_IN) begin
        tzero_q <= ~blk_in_ready_i;
      end else begin
        tzero_q <= tzero_q;
      end
    end else begin
      tzero_q <= tzero_q;
    end
  end


  // -- 2:1 MUX for Bulk IN vs Control Transfers -- //

  wire mux_tvalid_w, mux_tlast_w, mux_tkeep_w;
  wire [7:0] mux_tdata_w;

  wire blk_sel_w = xbulk == BLK_DATI_TX;
  wire ctl_sel_w = xctrl == CTL_DATI_TX;

  assign mux_tvalid_w = blk_sel_w ? blk_tvalid_i : ctl_sel_w ? ctl_tvalid_i : tzero_q;
  assign mux_tlast_w  = blk_sel_w ? blk_tlast_i : ctl_sel_w ? ctl_tlast_i : tzero_q;
  assign mux_tkeep_w  = blk_sel_w ? blk_tkeep_i : ctl_sel_w ? ctl_tkeep_i : 1'b0;
  assign mux_tdata_w  = blk_sel_w ? blk_tdata_i : ctl_sel_w ? ctl_tdata_i : 8'bx;

  generate
    if (USE_ULPI_TX_FIFO) begin : g_ulpi_tx_fifo

      // Using a FIFO allows Tx-data to be prefetched
      sync_fifo #(
          .WIDTH (10),
          .ABITS (4),
          .OUTREG(0)
      ) U_TXFIFO1 (
          .clock(clock),
          .reset(reset),

          .level_o(),

          .valid_i(mux_tvalid_w),
          .ready_o(mux_tready_w),
          .data_i ({mux_tkeep_w, mux_tlast_w, mux_tdata_w}),

          .valid_o(usb_tvalid_o),
          .ready_i(usb_tready_i),
          .data_o ({usb_tkeep_o, usb_tlast_o, usb_tdata_o})
      );

    end else begin : g_ulpi_tx_skid

      axis_skid #(
          .WIDTH (9),
          .BYPASS(PIPELINED == 0)
      ) U_AXIS_SKID1 (
          .clock(clock),
          .reset(reset),

          .s_tvalid(mux_tvalid_w),
          .s_tready(mux_tready_w),
          .s_tlast (mux_tlast_w),
          .s_tdata ({mux_tkeep_w, mux_tdata_w}),

          .m_tvalid(usb_tvalid_o),
          .m_tready(usb_tready_i),
          .m_tlast (usb_tlast_o),
          .m_tdata ({usb_tkeep_o, usb_tdata_o})
      );

    end
  endgenerate


  //
  //  Transaction FSM
  //
  //  Hierarchical, pipelined FSM that controls the relevant lower-level FSM,
  //  waits for it to finish, or handles any errors.
  //
  //  Todo:
  //   - should this FSM handle no-data responses ??
  //   - control the input MUX, and the output CE's
  ///
  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      err_code_q <= ER_NONE;
    end else begin
      case (state)
        // default: begin  // ST_IDLE
        ST_IDLE: begin
          //
          // Decode tokens until we see our address, and a valid endpoint
          ///
          if (tok_recv_i && tok_addr_i == usb_addr_i) begin
            if (tok_ping_i || usb_tuser_i[3:2] == TOK_IN || usb_tuser_i[3:2] == TOK_OUT) begin
              state <= ST_BULK;
              err_code_q <= tok_endp_i != ENDPOINT1 && tok_endp_i != ENDPOINT2 ? ER_ENDP : ER_NONE;
            end else if (usb_tuser_i[3:2] == TOK_SETUP) begin
              state <= ST_CTRL;
              err_code_q <= tok_endp_i != 4'h0 ? ER_ENDP : ER_NONE;
            end else begin
              // Either invalid endpoint, or unsupported transfer-type for the
              // requested endpoint.
              state <= ST_DUMP;
              err_code_q <= ER_TOKN;
            end
          end else begin
            state <= ST_IDLE;
            err_code_q <= ER_NONE;
          end
        end

        ST_CTRL: begin
          //
          // Wait for the USB to finish, and then return to IDLE
          ///
          if (xctrl == CTL_DONE) begin
            state <= ST_IDLE;
          end
        end

        ST_BULK: begin
          if (xbulk == BLK_DONE) begin
            state <= ST_IDLE;
          end
        end

        ST_DUMP: begin
          //
          // todo: Wait for the USB to finish, and then return to IDLE
          ///
          state <= ST_DUMP;
        end
      endcase
    end
  end


  //
  //  Bulk-Transfer Main FSM
  ///
  always @(posedge clock) begin
    if (state == ST_IDLE) begin
      xbulk   <= BLK_IDLE;
      fetch_q <= 1'b0;
      store_q <= 1'b0;
    end else begin
      case (xbulk)
        // default: begin  // BLK_IDLE
        BLK_IDLE: begin
          // If the main FSM has found a relevant token, start a Bulk Transfer
          if (state == ST_BULK) begin
            if (usb_tuser_i[3:2] == TOK_IN) begin
              xbulk   <= blk_in_ready_i ? BLK_DATI_TX : BLK_DATI_ZDP;
              fetch_q <= blk_in_ready_i;
              store_q <= 1'b0;
            end else begin
              xbulk   <= blk_out_ready_i ? BLK_DATO_RX : BLK_DATO_ERR;
              fetch_q <= 1'b0;
              store_q <= blk_out_ready_i;
            end
          end else begin
            fetch_q <= 1'b0;
            store_q <= 1'b0;
          end
        end

        BLK_DATI_TX, BLK_DATI_ZDP: begin
          // Send a zero-data packet, because we do not have a full packet, and
          // a ZDP will avoid timing-out 'libusb' ??
          if (usb_sent_i) begin
            xbulk <= BLK_DATI_ACK;
          end
        end

        BLK_DATI_ACK: begin
          // Wait for the host to 'ACK' the packet
          if (hsk_recv_i || terr_q) begin
            xbulk <= BLK_DONE;
          end
        end

        // Rx states for BULK OUT data //
        BLK_DATO_RX: begin
          if (usb_recv_i) begin
            xbulk <= BLK_DATO_ACK;
          end
        end

        BLK_DATO_ERR: begin
          if (usb_tvalid_i && usb_tready_o && usb_tlast_i) begin
            xbulk <= BLK_DATO_NAK;
          end
        end

        BLK_DATO_ACK, BLK_DATO_NAK: begin
          // todo: implement the PING protocol ...
          if (hsk_sent_i) begin
            xbulk <= BLK_DONE;
          end
        end

        BLK_DONE: begin
          store_q <= 1'b0;
          fetch_q <= 1'b0;
          if (state == ST_IDLE) begin
            xbulk <= BLK_IDLE;
          end
        end
      endcase
    end
  end


  // -- Turnaround Timer -- //

  // localparam TIMER = 91; // Value from the USB 2.0 spec.
  localparam TIMER = 255;
  localparam TBITS = $clog2(TIMER);
  localparam TSB = TBITS - 1;
  localparam TZERO = {TBITS{1'b0}};
  localparam TUNIT = {{TSB{1'b0}}, 1'b1};
  localparam [TSB:0] MAX_TURNAROUND = TIMER;

  reg actv_q;
  wire we_are_waiting;
  reg [TSB:0] tcount;
  wire [TBITS:0] tcnext;

  assign tcnext = tcount - TUNIT;
  assign we_are_waiting = tok_recv_i && (usb_tuser_i == {TOK_OUT, 2'b01} ||
                                         usb_tuser_i == {TOK_SETUP, 2'b01}) ||
                          usb_sent_i && (tuser_q == {DATA0, 2'b11} ||
                                         tuser_q == {DATA1, 2'b11}) ||
                          hsk_sent_i && (xctrl == CTL_SETUP_ACK ||
                                         xctrl == CTL_DATO_ACK);

  always @(posedge clock) begin
    if (reset) begin
      tcount <= TZERO;
      actv_q <= 1'b0;
      terr_q <= 1'b0;
    end else begin
      if (xctrl == CTL_STATUS_TX && usb_sent_i || we_are_waiting) begin
        tcount <= MAX_TURNAROUND;
        actv_q <= 1'b1;
        terr_q <= 1'b0;
      end else if (usb_recv_i || tok_recv_i || hsk_recv_i) begin
        actv_q <= 1'b0;
        terr_q <= 1'b0;
      end else if (actv_q) begin
        tcount <= tcnext[TSB:0];
        if (tcnext[TBITS]) begin
          actv_q <= 1'b0;
          terr_q <= 1'b1;
        end
      end else if (usb_idle_w) begin
        terr_q <= 1'b0;
      end
    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_state;
  reg [119:0] dbg_xctrl, dbg_xbulk;
  reg [47:0] dbg_pid;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_BULK: dbg_state = "BULK";
      ST_CTRL: dbg_state = "CTRL";
      ST_DUMP: dbg_state = "DUMP";
      default: dbg_state = "XXXX";
    endcase
  end

  always @* begin
    case (xbulk)
      BLK_IDLE: dbg_xbulk = "IDLE";
      BLK_DONE: dbg_xbulk = "DONE";

      BLK_DATI_TX:  dbg_xbulk = "DATI_TX";
      BLK_DATI_ZDP: dbg_xbulk = "DATI_ZDP";
      BLK_DATI_ACK: dbg_xbulk = "DATI_ACK";

      BLK_DATO_RX:  dbg_xbulk = "DATO_RX";
      BLK_DATO_ACK: dbg_xbulk = "DATO_ACK";
      BLK_DATO_ERR: dbg_xbulk = "DATO_ERR";

      default: dbg_xbulk = "UNKNOWN";
    endcase
  end

  always @* begin
    case (usb_tuser_i)
      `USBPID_OUT:   dbg_pid = "OUT";
      `USBPID_IN:    dbg_pid = "IN";
      `USBPID_SOF:   dbg_pid = "SOF";
      `USBPID_SETUP: dbg_pid = "SETUP";
      `USBPID_DATA0: dbg_pid = "DATA0"; 
      `USBPID_DATA1: dbg_pid = "DATA1"; 
      `USBPID_DATA2: dbg_pid = "DATA2"; 
      `USBPID_MDATA: dbg_pid = "MDATA"; 
      `USBPID_ACK:   dbg_pid = "ACK";
      `USBPID_NAK:   dbg_pid = "NAK";
      `USBPID_STALL: dbg_pid = "STALL";
      `USBPID_NYET:  dbg_pid = "NYET";
      `USBPID_PRE:   dbg_pid = "PRE";
      `USBPID_ERR:   dbg_pid = "ERR";
      `USBPID_SPLIT: dbg_pid = "SPLIT";
      `USBPID_PING:  dbg_pid = "PING";
      default:       dbg_pid = " ??? ";
    endcase
  end

`endif /* __icarus */


endmodule // protocol_layer
