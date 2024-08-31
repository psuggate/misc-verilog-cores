`timescale 1ns / 100ps
/**
 * Bulk IN End-Point.
 *
 * Emits frames with size >512B in multiple chunks, issuing a ZDP if the frame-
 * size is a multiple of 512.
 */
module ep_bulk_in #(
    parameter MAX_PACKET_LENGTH = 512,  // For HS-mode
    parameter PACKET_FIFO_DEPTH = 2048,
    parameter ENABLED = 1,
    parameter USE_ZDP = 0  // TODO
) (
    input clock,
    input reset,

    input set_conf_i,  // From CONTROL PIPE0
    input clr_conf_i,  // From CONTROL PIPE0

    input selected_i,  // From USB controller
    input ack_recv_i,  // From USB controller
    input timedout_i,  // From USB controller

    output ep_ready_o,
    output stalled_o,   // If invariants violated
    output parity_o,

    // From bulk data source
    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [7:0] s_tdata,

    // To USB/ULPI packet encoder MUX
    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [7:0] m_tdata
);

  // Counter parameters, for the number of bytes in the current packet
  localparam CBITS = $clog2(MAX_PACKET_LENGTH);
  localparam CSB = CBITS - 1;
  localparam CZERO = {CBITS{1'b0}};
  localparam CMAX = {CBITS{1'b1}};

  // Address-/level- bits, for the FIFO
  localparam ABITS = $clog2(PACKET_FIFO_DEPTH);
  localparam ASB = ABITS - 1;

  //
  //  TODO
  // ======
  //  1. generate 'save' strobes when source-data > max packet size;
  //  2. 'next' strobes on 'ACK' handshakes (from USB host);
  //  3. 'redo' strobes on 'selected', when an 'ACK' has not been received;
  //  4. counter for source-data (bytes of the current packet);
  //  5. counter for transmit-data, to queue ZDP's at max-packet-sizes;
  //
  localparam [2:0] RX_HALT = 3'b001;
  localparam [2:0] RX_RECV = 3'b010;
  localparam [2:0] RX_FULL = 3'b100;

  localparam [4:0] TX_IDLE = 5'b00001;
  localparam [4:0] TX_SEND = 5'b00010;
  localparam [4:0] TX_WAIT = 5'b00100;
  localparam [4:0] TX_NONE = 5'b01000;
  localparam [4:0] TX_REDO = 5'b10000;

  reg [2:0] recv, rnxt;
  reg [4:0] send, snxt;

  wire tready_w;
  wire tvalid_r, tready_r, tlast_r;
  wire save_w, redo_w, next_w;
  reg rst_q, par_q, set_q, zdp_q;
  reg [CSB:0] rcount, scount;
  wire [CBITS:0] rcnext, scnext;
  wire [ASB:0] level_w;


  // Todo: packet ready when
  //  - there is a packet(-chunk) in the FIFO; OR,
  //  - a ZDP needs to be transmitted?
  assign ep_ready_o = tvalid_r | zdp_q;  // send == TX_NONE;

  assign stalled_o = ~set_q;
  assign parity_o = par_q;

  assign s_tready = tready_w && set_q && recv == RX_RECV;

  assign m_tvalid = send == TX_SEND && tvalid_r || send == TX_NONE;
  assign tready_r = send == TX_SEND && m_tready;
  assign m_tlast = send == TX_SEND && tlast_r || send == TX_NONE;
  assign m_tkeep = send == TX_SEND;


  // -- FIFO Reset/Clear -- //

  always @(posedge clock) begin
    rst_q <= reset || set_conf_i || clr_conf_i;
    if (reset || clr_conf_i) begin
      set_q <= 1'b0;
    end else if (set_conf_i) begin
      set_q <= 1'b1;
    end
  end


  // -- DATA0/1 Parity -- //

  always @(posedge clock) begin
    if (set_conf_i) begin
      // As per the USB 2.0 spec, certain 'SET CONFIGURATION' events are
      // required to reset the parity/sequence bit.
      par_q <= 1'b0;
    end else if (send == TX_WAIT && selected_i && ack_recv_i) begin
      par_q <= ~par_q;
    end
  end


  // -- Receive Counter -- //

  assign rcnext = s_tlast ? {1'b0, CZERO} : rcount + 1;

  always @(posedge clock) begin
    if (set_conf_i || ENABLED != 1) begin
      rcount <= CZERO;
    end else begin
      if (s_tvalid && tready_w) begin
        rcount <= rcnext[CSB:0];
      end
    end
  end


  // -- Transmit (or, Send) Counter -- //

  assign scnext = m_tlast ? {1'b0, CZERO} : scount + 1;

  always @(posedge clock) begin
    if (set_conf_i || ENABLED != 1) begin
      scount <= CZERO;
    end else begin
      if (m_tvalid && m_tready) begin
        scount <= scnext[CSB:0];
      end
    end
  end


  // -- FSM(s) for Bulk IN Transfers -- //

  // Receive (from upstream) state-machine logic
  assign save_w = s_tvalid && tready_w && (s_tlast || rcount == CMAX);

  always @(posedge clock) begin
    if (clr_conf_i) begin
      recv <= RX_HALT;
    end else if (set_conf_i) begin
      recv <= RX_RECV;
    end else begin
      case (recv)
        RX_HALT: begin
          recv <= recv;
        end

        RX_RECV:
        // Don't prefetch if we can not store a full-sized packet, or else we
        // may stall the AXI4-Stream (which could be a problem if it is
        // shared).
        if (save_w && level_w >= MAX_PACKET_LENGTH) begin
          recv <= RX_FULL;
        end

        RX_FULL:
        // The only way for 'level' to fall is via 'ACK', so this condition is
        // sufficient.
        if (level_w < MAX_PACKET_LENGTH) begin
          recv <= RX_RECV;
        end
      endcase
    end
  end

  // Transmit (downstream) to ULPI encoder, state-machine logic
  assign redo_w = send == TX_WAIT && selected_i && timedout_i;
  assign next_w = send == TX_WAIT && selected_i && ack_recv_i;

  always @* begin
    snxt = send;

    case (send)
      TX_IDLE:
      if (selected_i) begin
        snxt = tvalid_r ? TX_SEND : TX_NONE;
      end

      // Transferring data from source to USB encoder (via the packet FIFO).
      TX_SEND:
      if (tvalid_r && m_tready && tlast_r) begin
        snxt = TX_WAIT;
      end

      // After sending a packet, wait for an ACK/ERR response.
      TX_WAIT:
      if (selected_i && ack_recv_i) begin
        snxt = zdp_q ? TX_NONE : TX_IDLE;
      end else if (selected_i && timedout_i) begin
        snxt = TX_REDO;
      end

      // Rest of packet has already been sent, so transmit a ZDP
      TX_NONE:
      if (m_tvalid && m_tready && m_tlast) begin
        snxt = TX_WAIT;
      end

      // Repeat the previous packet(-chunk), as an 'ACK' was not received.
      TX_REDO:
      if (selected_i) begin
        snxt = TX_SEND;
      end
    endcase

    if (set_q != 1'b1 || ENABLED != 1) begin
      snxt = TX_IDLE;
    end
  end

  always @(posedge clock) begin
    send <= snxt;

    // Todo:
    if (!set_q || send == TX_IDLE) begin
      zdp_q <= 1'b0;
    end else if (scount == CMAX && tvalid_r && tready_r && tlast_r) begin
      zdp_q <= 1'b1;
    end
  end


  // -- Packet FIFO with Repeat-Last Packet -- //

  packet_fifo #(
      .WIDTH(8),
      .DEPTH(PACKET_FIFO_DEPTH),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(1),
      .LAST_ON_SAVE(1),
      .NEXT_ON_LAST(0),
      .USE_LENGTH(1),
      .MAX_LENGTH(MAX_PACKET_LENGTH),
      .OUTREG(2)
  ) U_TX_FIFO1 (
      .clock(clock),
      .reset(rst_q),

      .level_o(level_w),
      .drop_i (1'b0),
      .save_i (save_w),
      .redo_i (redo_w),
      .next_i (next_w),

      .s_tvalid(s_tvalid),
      .s_tready(tready_w),
      .s_tlast (s_tlast),
      .s_tkeep (s_tvalid),
      .s_tdata (s_tdata),

      .m_tvalid(tvalid_r),
      .m_tready(tready_r),
      .m_tlast (tlast_r),
      .m_tdata (m_tdata)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_recv;
  reg [39:0] dbg_send;

  always @* begin
    case (recv)
      RX_HALT: dbg_recv = "HALT";
      RX_RECV: dbg_recv = "RECV";
      RX_FULL: dbg_recv = "FULL";
      default: dbg_recv = " ?? ";
    endcase
  end

  always @* begin
    case (send)
      TX_IDLE: dbg_send = "IDLE";
      TX_SEND: dbg_send = "SEND";
      TX_WAIT: dbg_send = "WAIT";
      TX_NONE: dbg_send = "NONE";
      TX_REDO: dbg_send = "REDO";
      default: dbg_send = " ?? ";
    endcase
  end

`endif  /* __icarus */


endmodule  // ep_bulk_in
