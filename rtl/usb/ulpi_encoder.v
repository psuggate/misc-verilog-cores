`timescale 1ns / 100ps
module ulpi_encoder (
    input clock,
    input reset,

    output ulpi_enabled_o,

    input [1:0] LineState,

    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [3:0] s_tuser,
    input [7:0] s_tdata,

    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    output [7:0] ulpi_data
);

  `include "usb_crc.vh"

  // -- Constants -- //

  // FSM states
  localparam [6:0] TX_REGW = 7'h01;
  localparam [6:0] TX_IDLE = 7'h02;
  localparam [6:0] TX_XPID = 7'h04;
  localparam [6:0] TX_DATA = 7'h08;
  localparam [6:0] TX_CRC0 = 7'h10;
  localparam [6:0] TX_LAST = 7'h20;
  localparam [6:0] TX_DONE = 7'h40;


  // -- Signals & State -- //

  reg [6:0] xsend;
  wire HighSpeed;

  // Signals for sending initialisation commands & settings to the PHY.
  wire phy_set_w, phy_get_w, phy_stp_w, phy_chp_w, phy_bsy_w, phy_ack_w;
  wire [7:0] phy_adr_w, phy_val_w;


  // -- ULPI Encoder FSM -- //

  wire tlast_w = tvalid ? tlast : s_tlast;  // todo: handshakes, ZDPs, and CRCs
  wire [7:0] tdata_w = tvalid ? tdata : s_tdata;

  always @(posedge clock) begin
    if (dir_q || ulpi_dir) begin
      xsend <= TX_IDLE;
    end else begin
      case (xsend)
        default: begin  // TX_IDLE
          xsend <= phy_cmd_w ? TX_REGW : s_tvalid ? TX_XPID : TX_IDLE;

          // Upstream TREADY signal
          s_tready <= phy_cmd_w || s_tvalid ? 1'b0 : HighSpeed;

          // Latch the first byte (using temp. reg.)
          tvalid <= s_tready && s_tvalid;
          tlast <= s_tlast;
          tdata <= s_tdata;

          // Output the PID byte
          ulpi_stp <= phy_cmd_w && phy_stp_w ? 1'b1 : 1'b0;
          ulpi_data <= phy_cmd_w ? phy_adr_w : pid_w;
        end

        TX_REGW: begin
          if (ulpi_nxt) begin
            xsend <= TX_LAST;
            ulpi_data <= phy_val_w;
          end
        end

        TX_XPID: begin
          // Output PID has been accepted ??
          xsend     <= ulpi_nxt ? TX_DATA : xsend;

          // If so, we can receive another byte
          s_tready  <= ulpi_nxt ? 1'b1 : 1'b0;

          // Start transferring the packet data
          ulpi_stp  <= ulpi_nxt ? tlast_w : 1'b0;
          ulpi_data <= ulpi_nxt ? tdata_w : ulpi_data;
        end

        TX_DATA: begin
          xsend     <= ulpi_nxt && tlast_w ? TX_CRC0 : xsend;

          s_tready  <= sready_next;

          // Continue transferring the packet data
          ulpi_stp  <= 1'b0;
          ulpi_data <= ulpi_nxt ? tdata_w : ulpi_data;
        end

        TX_CRC0: begin
          // Send 1st CRC16 byte
          xsend     <= ulpi_nxt ? TX_LAST : xsend;

          s_tready  <= 1'b0;

          ulpi_stp  <= 1'b0;
          ulpi_data <= ulpi_nxt ? tdata_w : ulpi_data;
        end

        TX_LAST: begin
          // Send 2nd (and last) CRC16 byte
          xsend     <= ulpi_nxt ? TX_DONE : xsend;

          s_tready  <= 1'b0;

          ulpi_stp  <= ulpi_nxt;
          ulpi_data <= ulpi_nxt ? 8'd0 : tdata_w;
        end

        TX_DONE: begin
          // Wait for the PHY to signal that the USB LineState represents End-of
          // -Packet (EOP), indicating that the packet has been sent
          //
          // Todo: the USB 2.0 spec. also gives a tick-count until the packet is
          //   considered to be sent ??
          // Todo: should get the current 'LineState' from the ULPI decoder
          //   module, as this module is Tx-only ??
          //
          xsend     <= dir_q && ulpi_dir && !ulpi_nxt && LineState == LS_EOP ? TX_IDLE : xsend;

          s_tready  <= 1'b0;

          ulpi_stp  <= 1'b0;
          ulpi_data <= 8'd0;
        end

      endcase
    end
  end


  // -- ULPI Initialisation FSM -- //

  ulpi_line_state #(
      .HIGH_SPEED(1)
  ) U_ULPI_LS0 (
      .clock(clock),
      .reset(reset),

      .ulpi_dir (ulpi_dir),
      .LineState(LineState),
      .HighSpeed(HighSpeed),

      .phy_write_o(phy_set_w),
      .phy_read_o (phy_get_w),
      .phy_chirp_o(phy_chp_w),
      .phy_stop_o (phy_stp_w),
      .phy_busy_i (phy_bsy_w),
      .phy_done_i (phy_ack_w),
      .phy_addr_o (phy_adr_w),
      .phy_data_o (phy_val_w)
  );


endmodule  // ulpi_encoder
