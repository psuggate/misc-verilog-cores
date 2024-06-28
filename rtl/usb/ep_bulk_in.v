`timescale 1ns / 100ps
module ep_bulk_in
  #(
    parameter ENABLED = 1,
    parameter USE_ZDP = 0 // TODO
  )
  (
   input clock,
   input reset,

   input set_conf_i, // From CONTROL PIPE0
   input clr_conf_i, // From CONTROL PIPE0

   input selected_i, // From USB decoder
   input ack_recv_i, // From USB decoder
   input err_recv_i, // From USB decoder

   // From bulk data source
   input s_tvalid,
   output s_tready,
   input s_tkeep,
   input s_tlast,
   input [7:0] s_tdata,

   // To USB/ULPI packet encoder MUX
   output m_tvalid,
   input m_tready,
   output m_tkeep,
   output m_tlast,
   output [3:0] m_tuser,
   output [7:0] m_tdata
   );

  localparam [3:0] DATA0 = 4'b0011;
  localparam [3:0] DATA1 = 4'b1011;
  localparam [3:0] NAK   = 4'b1010;
  localparam [3:0] STALL = 4'b1110;

  localparam [4:0] ST_HALT = 5'b00001;
  localparam [4:0] ST_IDLE = 5'b00010;
  localparam [4:0] ST_SEND = 5'b00100;
  localparam [4:0] ST_NONE = 5'b01000;
  localparam [4:0] ST_WAIT = 5'b10000;

  reg [4:0] snext, state;
  wire tvalid_w, tready_w, tlast_w, tkeep_w;
  reg parity, enabled;
  reg [3:0] pid_q;


  assign tvalid_w = state == ST_SEND && s_tvalid || state == ST_NONE;
  assign s_tready = tready_w && state == ST_SEND;
  assign tkeep_w  = s_tkeep && state != ST_NONE;
  assign tlast_w  = s_tlast || state == ST_NONE;
  assign m_tuser  = pid_q;


  // -- FSM for Bulk IN Transfers -- //

  always @* begin
    snext = state;

    if (state == ST_IDLE && selected_i) begin
      snext = s_tvalid ? ST_SEND : ST_NONE;
    end
    // Transferring data from source to USB encoder.
    if (state == ST_SEND && s_tvalid && s_tlast && tready_w) begin
      snext = ST_WAIT;
    end
    // No data to send, so transmit a NAK (TODO: or ZDP)
    if (state == ST_NONE && tready_w) begin
      snext = enabled ? ST_IDLE : ST_HALT;
    end
    // After sending a packet, wait for an ACK/ERR response.
    if (state == ST_WAIT && (ack_recv_i || err_recv_i)) begin
      snext = ST_IDLE;
    end

    if (clr_conf_i) begin
      snext = ST_HALT;
    end else if (set_conf_i) begin
      snext = ST_IDLE;
    end

    // Issue STALL if we get a requested prior to being configured
    if (state == ST_HALT && selected_i) begin
      snext = ST_NONE;
    end
  end

  always @(posedge clock) begin
    if (reset || ENABLED != 1) begin
      state <= ST_HALT;
      enabled <= 1'b0;
      pid_q <= STALL;
    end else begin
      state <= snext;

      if (clr_conf_i) begin
        enabled <= 1'b0;
      end else if (set_conf_i) begin
        enabled <= 1'b1;
      end

      case (state)
        ST_HALT: pid_q <= STALL;
        ST_IDLE: begin
          // Issue NAK response unless 'Bulk IN' data is already waiting
          if (s_tvalid) begin
            pid_q <= parity ? DATA1 : DATA0;
          end else begin
            pid_q <= NAK;
          end
        end
        ST_NONE: pid_q <= pid_q;
        ST_SEND: pid_q <= pid_q;
        ST_WAIT: pid_q <= pid_q;
      endcase
    end
  end


  // -- DATA0/1 Parity -- //

  always @(posedge clock) begin
    if (reset || set_conf_i) begin
      parity <= 1'b0;
    end else begin
      if (state == ST_WAIT && ack_recv_i) begin
        parity <= ~parity;
      end
    end
  end


  // -- Output Registers -- //

  axis_skid
 #(
   .BYPASS(0),
   .WIDTH(9)
   ) SKID0
   (
    .clock   (clock),
    .reset   (reset),

    .s_tvalid(tvalid_w),
    .s_tready(tready_w),
    .s_tlast (tlast_w),
    .s_tdata ({tkeep_w, s_tdata}),

    .m_tvalid(m_tvalid),
    .m_tready(m_tready),
    .m_tlast (m_tlast),
    .m_tdata ({m_tkeep, m_tdata})
    );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_state;
  reg [47:0] dbg_pid;

  always @* begin
    case (state)
      ST_HALT: dbg_state = "HALT";
      ST_IDLE: dbg_state = "IDLE";
      ST_SEND: dbg_state = "SEND";
      ST_NONE: dbg_state = "NONE";
      ST_WAIT: dbg_state = "WAIT";
      default: dbg_state = " ?? ";
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
