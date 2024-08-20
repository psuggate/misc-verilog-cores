`timescale 1ns / 100ps
/**
 * Bulk IN End-Point.
 *
 * Emits frames with size >512B in multiple chunks, issuing a ZDP if the frame-
 * size is a multiple of 512.
 */
module ep_bulk_in
  #(
    parameter USB_MAX_PACKET_SIZE = 512, // For HS-mode
    parameter PACKET_FIFO_DEPTH = 2048,
    parameter ENABLED = 1,
    parameter CONSTANT = 0,
    parameter USE_ZDP = 0 // TODO
  )
  (
   input clock,

   input set_conf_i, // From CONTROL PIPE0
   input clr_conf_i, // From CONTROL PIPE0

   input selected_i, // From USB controller
   input ack_recv_i, // From USB controller
   input timedout_i, // From USB controller

   output ep_ready_o,
   output stalled_o, // If invariants violated
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
  localparam CBITS = $clog2(USB_MAX_PACKET_SIZE);
  localparam CSB   = CBITS - 1;
  localparam CZERO = {CBITS{1'b0}};
  localparam CMAX  = {CBITS{1'b1}};

  // Address-/level- bits, for the FIFO
  localparam ABITS = $clog2(PACKET_FIFO_DEPTH);
  localparam ASB   = ABITS - 1;

  //
  // TODO
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
  localparam [4:0] TX_NONE = 5'b00100;
  localparam [4:0] TX_WAIT = 5'b01000;
  localparam [4:0] TX_REDO = 5'b10000;

  reg [2:0] recv, rnxt;
  reg [4:0] send, snxt;

  wire tvalid_w, tready_w, tlast_w, tkeep_w;
  wire save_w, redo_w, next_w;
  reg parity, set_q, zdp_q;
  reg [CSB:0] rcount, scount;
  wire [CBITS:0] rcnext, scnext;
  wire [ASB:0] level_w;


  assign stalled_o = ~set_q;
  assign parity_o  = parity;


  // -- FSM for Bulk IN Transfers -- //

  // Receive (from upstream) state-machine logic
  assign s_tready = tready_w && set_q && recv == RX_RECV;
  assign save_w = s_tvalid && s_tready && recv == RX_RECV && rcount == CMAX;

  always @* begin
    rnxt = recv;

    if (recv == RX_HALT) begin
      rnxt = set_conf_i ? RX_RECV : RX_HALT;
    end
    // Don't prefetch too far ahead, for latency reasons ??
    // Todo:
    //  - desirable ??
    //  - use a register, 'full_q', to improve the circuit performance ??
    if (recv == RX_RECV && save_w && level_w >= USB_MAX_PACKET_SIZE) begin
      rnxt = RX_FULL;
    end
  end

  // Transmit (downstream) to ULPI encoder, state-machine logic
  assign redo_w = send == TX_WAIT && timedout_i;
  assign next_w = send == TX_WAIT && ack_recv_i;

  assign tvalid_w = send == TX_SEND && s_tvalid || send == TX_NONE;
  assign tkeep_w  = s_tkeep && send != TX_NONE;
  assign tlast_w  = s_tlast || send == TX_NONE;

  always @* begin
    snxt = send;

    if (send == TX_IDLE && selected_i) begin
      snxt = s_tvalid ? TX_SEND : TX_NONE;
    end
    // Transferring data from source to USB encoder.
    if (send == TX_SEND && s_tvalid && s_tlast && tready_w) begin
      snxt = TX_WAIT;
    end
    // No data to send, so transmit a NAK (TODO: or ZDP)
    if (send == TX_NONE && tready_w) begin
      snxt = set_q ? TX_IDLE : TX_HALT;
    end
    // After sending a packet, wait for an ACK/ERR response.
    if (send == TX_WAIT && (ack_recv_i || err_recv_i)) begin
      snxt = TX_IDLE;
    end

    // Issue STALL if we get a requested prior to being configured
    if (send == TX_HALT && selected_i) begin
      snxt = TX_NONE;
    end
  end


  assign rcnext = rcount + 1;
  assign scnext = scount + 1;

  always @(posedge clock) begin
  end

  always @(posedge clock) begin
    if (clr_conf_i || ENABLED != 1) begin
      recv   <= RX_HALT;
      send   <= TX_IDLE;
      set_q  <= 1'b0;
      zdp_q  <= 1'b0;
      rcount <= CZERO;
      scount <= CZERO;
    end else begin

      // Rx update
      recv   <= rnxt;
      if (s_tvalid && tready_w) begin
        // Todo: reset count on 'tlast'
        rcount <= rcnext[CSB:0];
      end

      // Tx update
      if (set_conf_i) begin
        send   <= TX_IDLE;
        set_q  <= 1'b1;
        scount <= CZERO;
        zdp_q  <= 1'b0;
      end else begin
        send   <= snxt;
        set_q  <= set_q;
        if (m_tvalid && m_tready) begin
          scount <= scnext[CSB:0];
        end
        if (scount == CMAX && tlast_w && tvalid_w && tready_w) begin
          // Todo:
          zdp_q <= 1'b1;
        end
      end

    end
  end


  // -- DATA0/1 Parity -- //

  always @(posedge clock) begin
    if (set_conf_i) begin
      parity <= 1'b0;
    end else begin
      if (send == TX_WAIT && ack_recv_i) begin
        parity <= ~parity;
      end
    end
  end


  // -- Output Registers -- //

  packet_fifo
    #( .WIDTH(8),
       .DEPTH(PACKET_FIFO_DEPTH),
       .STORE_LASTS(1),
       .SAVE_ON_LAST(1),
       .SAVE_TO_LAST(1),
       .NEXT_ON_LAST(0),
       .USE_LENGTH(1),
       .MAX_LENGTH(USB_MAX_PACKET_SIZE),
       .OUTREG(2)
       )
  U_TX_FIFO1
    ( .clock  (clock),
      .reset  (recv == RX_HALT),

      .level_o(level_w),
      .drop_i (1'b0),
      .save_i (save_w),
      .redo_i (redo_w),
      .next_i (next_w),

      .valid_i(s_tvalid),
      .ready_o(tready_w),
      .last_i (s_tlast),
      .data_i (s_tdata),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .last_o (tlast_w),
      .data_o (m_tdata)
      );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_recv;
  reg [39:0] dbg_send;
  reg [47:0] dbg_pid;

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
      TX_HALT: dbg_send = "HALT";
      TX_IDLE: dbg_send = "IDLE";
      TX_SEND: dbg_send = "SEND";
      TX_NONE: dbg_send = "NONE";
      TX_WAIT: dbg_send = "WAIT";
      default: dbg_send = " ?? ";
    endcase
  end

  always @* begin
    case (pid_q)
      STALL:   dbg_pid = "STALL";
      DATA0:   dbg_pid = "DATA0";
      DATA1:   dbg_pid = "DATA1";
      NAK:     dbg_pid = "NAK  ";
      default: dbg_pid = " ??? ";
    endcase
  end

`endif /* __icarus */


endmodule // ep_bulk_in
