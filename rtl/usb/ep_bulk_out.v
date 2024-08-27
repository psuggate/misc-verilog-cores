`timescale 1ns / 100ps
/**
 * Bulk OUT End-Point.
 *
 * Re-assembles frames with size >512B from multiple chunks, and receipt of a
 * ZDP indicates that the frame-size is a multiple of 512, generating a 'tlast'.
 */
module ep_bulk_out #(
    parameter USB_MAX_PACKET_SIZE = 512,  // For HS-mode
    parameter PACKET_FIFO_DEPTH = 2048,
    parameter ENABLED = 1,
    parameter DUMPSTER = 1,
    parameter IGNORE_ZDP = 1  // TODO
) (
    input clock,
    input reset,

    input set_conf_i,  // From CONTROL PIPE0
    input clr_conf_i,  // From CONTROL PIPE0

    input selected_i,  // From USB controller
    input rx_error_i,  // Timed-out or CRC16 error
    input ack_sent_i,

    output ep_ready_o,
    output stalled_o,   // If invariants violated
    output parity_o,

    // From USB/ULPI packet decoder
    input s_tvalid,
    output s_tready,  // Only asserted when space for at least one packet
    input s_tkeep,
    input s_tlast,
    input [7:0] s_tdata,

    // To bulk data sink
    output m_tvalid,  // Only asserted after CRC16 succeeds
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [7:0] m_tdata
);

  // Counter parameters, for the number of bytes in the current packet
  localparam CBITS = $clog2(USB_MAX_PACKET_SIZE);
  localparam CSB = CBITS - 1;
  localparam CZERO = {CBITS{1'b0}};
  localparam CMAX = {CBITS{1'b1}};

  // Address-/level- bits, for the FIFO
  localparam ABITS = $clog2(PACKET_FIFO_DEPTH);
  localparam ASB = ABITS - 1;

  localparam [4:0] ST_HALT = 5'b00001;
  localparam [4:0] ST_IDLE = 5'b00010;
  localparam [4:0] ST_RECV = 5'b00100;
  localparam [4:0] ST_SAVE = 5'b01000;
  localparam [4:0] ST_FULL = 5'b10000;

  reg [4:0] snext, state;
  reg par_q, rst_q, rdy_q;
  reg save_q, drop_q, full_q, zero_q;
  wire [  ASB:0] level_w;
  wire [ABITS:0] space_w;
  wire tvalid_w, tready_w;

  assign stalled_o = state == ST_HALT;
  assign parity_o = par_q;
  assign ep_ready_o = rdy_q;
  assign tvalid_w = state == ST_RECV && s_tvalid && s_tkeep;
  assign s_tready = tready_w && state == ST_RECV;
  assign m_tkeep = m_tvalid;

  // Goes negative when there is no longer space for 'USB_MAX_PACKET_SIZE' to be
  // received.
  assign space_w = PACKET_FIFO_DEPTH - level_w - USB_MAX_PACKET_SIZE - 1;

  // -- End-Point Reset & Parity Flags -- //

  always @(posedge clock) begin
    if (reset || set_conf_i) begin
      rst_q <= 1'b1;
      par_q <= 1'b0;
      rdy_q <= 1'b0;
    end else begin
      rst_q <= 1'b0;

      if (save_q) begin
        par_q <= ~par_q;
      end

      if (state == ST_IDLE) begin
        rdy_q <= 1'b1;
      end else if (state == ST_HALT || state == ST_FULL) begin
        rdy_q <= 1'b0;
      end
    end
  end

  // -- Packet FIFO Control & Status Signals -- //

  always @(posedge clock) begin
    if (reset || set_conf_i) begin
      save_q <= 1'b0;
      drop_q <= 1'b0;
      full_q <= 1'b0;
      zero_q <= 1'b1;  // Todo: not required !?
    end else begin
      save_q <= state == ST_SAVE && ack_sent_i && (IGNORE_ZDP || !zero_q);
      drop_q <= state == ST_RECV && rx_error_i;
      full_q <= space_w[ABITS];

      // Detect ZDP's, as we do not store them
      if (state == ST_IDLE && selected_i) begin
        zero_q <= 1'b1;
      end else if (state == ST_RECV && s_tvalid && s_tready && s_tkeep) begin
        zero_q <= 1'b0;
      end
    end
  end


  // -- FSM for Bulk IN Transfers -- //

  always @* begin
    snext = state;
    case (state)
      ST_HALT:
      if (set_conf_i) begin
        snext = ST_IDLE;
      end
      ST_IDLE:
      if (selected_i) begin
        snext = ST_RECV;
      end
      ST_RECV:
      if (!selected_i) begin
        snext = ST_HALT;
      end else if (s_tvalid && s_tready && s_tlast) begin
        snext = ST_SAVE;
      end else if (rx_error_i) begin
        snext = ST_IDLE;
      end
      ST_SAVE:
      if (ack_sent_i) begin
        snext = full_q ? ST_FULL : ST_IDLE;
      end
      ST_FULL:
      if (!full_q) begin
        snext = ST_IDLE;
      end else if (selected_i) begin
        snext = ST_HALT;
      end
      default: snext = 'bx;
    endcase
  end

  always @(posedge clock) begin
    if (reset || clr_conf_i || ENABLED != 1) begin
      state <= ST_HALT;
    end else begin
      state <= snext;
    end
  end


  // -- Output Packet FIFO with Drop-Packet-on-Failure -- //

  packet_fifo #(
      .WIDTH(8),
      .DEPTH(PACKET_FIFO_DEPTH),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(0),  // save on CRC16-valid
      .NEXT_ON_LAST(1),
      .USE_LENGTH(0),
      .MAX_LENGTH(USB_MAX_PACKET_SIZE),
      .OUTREG(2)
  ) U_TX_FIFO1 (
      .clock(clock),
      .reset(rst_q),

      .level_o(level_w),

      .drop_i(drop_q),
      .save_i(save_q),
      .redo_i(1'b0),
      .next_i(1'b0),

      .valid_i(tvalid_w),
      .ready_o(tready_w),
      .last_i (s_tlast),
      .data_i (s_tdata),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .last_o (m_tlast),
      .data_o (m_tdata)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_state;

  always @* begin
    case (state)
      ST_HALT: dbg_state = "HALT";
      ST_IDLE: dbg_state = "IDLE";
      ST_RECV: dbg_state = "RECV";
      ST_SAVE: dbg_state = "SAVE";
      ST_FULL: dbg_state = "FULL";
      default: dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */


endmodule  /* ep_bulk_out */
