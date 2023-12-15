`timescale 1ns / 100ps
module ulpi_encoder (
    input clock,
    input reset,

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
  localparam [6:0] TX_INIT = 7'h01;
  localparam [6:0] TX_IDLE = 7'h02;
  localparam [6:0] TX_XPID = 7'h04;
  localparam [6:0] TX_DATA = 7'h08;
  localparam [6:0] TX_CRC0 = 7'h10;
  localparam [6:0] TX_LAST = 7'h20;
  localparam [6:0] TX_DONE = 7'h40;


  // -- Signals & State -- //

  reg [6:0] xsend;


  // -- ULPI Encoder FSM -- //

  wire tlast_w = tvalid ? tlast : s_tlast;  // todo: handshakes, ZDPs, and CRCs
  wire [7:0] tdata_w = tvalid ? tdata : s_tdata;

  always @(posedge clock) begin
    if (dir_q || ulpi_dir) begin
      xsend <= state == STATE_IDLE ? TX_IDLE : TX_INIT;
    end else begin
      case (xsend)
        default: begin  // TX_INIT
          // todo: this state not required, just use the 'if'-statement above ??
          xsend <= state == STATE_IDLE ? TX_IDLE : TX_INIT;
        end

        TX_IDLE: begin
          xsend <= s_tvalid ? TX_XPID : TX_IDLE;

          // Upstream TREADY signal
          s_tready <= s_tvalid ? 1'b0 : 1'b1;

          // Latch the first byte (using temp. reg.)
          tvalid <= s_tready && s_tvalid;
          tlast <= s_tlast;
          tdata <= s_tdata;

          // Output the PID byte
          ulpi_stp <= 1'b0;
          ulpi_data <= pid_w;
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
          xsend     <= dir_q && ulpi_dir && !ulpi_nxt && line_state == LS_EOP ? TX_IDLE : xsend;

          s_tready  <= 1'b0;

          ulpi_stp  <= 1'b0;
          ulpi_data <= 8'd0;
        end

      endcase
    end
  end


  // -- ULPI Initialisation FSM -- //

  always @(posedge ulpi_clk) begin
    if (reset) begin
      state <= STATE_INIT;
      ulpi_data_out_buf <= 8'h00;
    end else if (dir_q || ulpi_dir) begin
      // We are not driving //
      state <= state;
      snext <= 4'bx;
      reg_data <= 8'bx;
    end else begin
      // We are driving //
      case (state)
        default: begin  // STATE_INIT
          state <= STATE_WRITE_REGA;
          snext <= STATE_SWITCH_FSSTART;
          ulpi_data_out_buf <= 8'h8A;
          reg_data <= 8'h00;
        end

        // Update ULPI registers
        STATE_WRITE_REGA: begin
          if (ulpi_nxt) begin
            state <= STATE_WRITE_REGD;
            ulpi_data_out_buf <= reg_data;
            reg_data <= 8'bx;
          end else begin
            state <= STATE_WRITE_REGA;
            ulpi_data_out_buf <= ulpi_data_out_buf;
            reg_data <= reg_data;
          end
          snext <= snext;
        end

        STATE_WRITE_REGD: begin
          if (ulpi_nxt) begin
            state <= STATE_STP;
            ulpi_data_out_buf <= 8'h00;
          end else begin
            state <= STATE_WRITE_REGD;
            ulpi_data_out_buf <= ulpi_data_out_buf;
          end
          snext <= snext;
          reg_data <= 8'bx;
        end

        STATE_RESET: begin
          if (HIGH_SPEED == 1) begin
            state <= hs_enabled ? STATE_SWITCH_FSSTART : STATE_CHIRP_START;
          end else if (usb_line_state != 2'b00) begin
            state <= STATE_IDLE;
          end else begin
            state <= state;
          end
          snext <= 4'bx;
          ulpi_data_out_buf <= 8'h00;
          reg_data <= 8'bx;
        end

        STATE_SUSPEND: begin
          state <= usb_line_state != 2'b01 ? STATE_IDLE : STATE_SUSPEND;
          snext <= 4'bx;
          ulpi_data_out_buf <= 8'h00;
          reg_data <= 8'bx;
        end

        STATE_STP: begin
          state <= snext;
          snext <= 4'bx;
          ulpi_data_out_buf <= 8'h00;
          reg_data <= 8'bx;
        end

        STATE_IDLE: begin
          if (usb_line_state == 2'b00 && state_counter > RESET_TIME) begin
            state <= STATE_RESET;
            ulpi_data_out_buf <= 8'h00;
          end else if (!hs_enabled && usb_line_state == 2'b01 && state_counter > SUSPEND_TIME) begin
            state <= STATE_SUSPEND;
            ulpi_data_out_buf <= 8'h00;
          end else if (axis_tx_tvalid_i) begin
            ulpi_data_out_buf <= {4'b0100, axis_tx_tdata_i[3:0]};

            if (axis_tx_tlast_i) begin
              state <= STATE_TX_LAST;
            end else begin
              state <= STATE_TX;
            end
          end
          snext <= 4'bx;
          reg_data <= 8'bx;
        end

        STATE_TX: begin
          if (ulpi_nxt) begin
            if (axis_tx_tvalid_i && !buf_valid) begin
              state <= axis_tx_tlast_i ? STATE_TX_LAST : STATE_TX;
              ulpi_data_out_buf <= axis_tx_tdata_i;
            end else if (buf_valid) begin
              state <= buf_last ? STATE_TX_LAST : STATE_TX;
              ulpi_data_out_buf <= buf_data;
            end else begin
              state <= state;
              ulpi_data_out_buf <= 8'h00;
            end
          end else begin
            state <= state;
            ulpi_data_out_buf <= ulpi_data_out_buf;
          end
          snext <= 4'bx;
          reg_data <= 8'bx;
        end

        STATE_TX_LAST: begin
          if (ulpi_nxt) begin
            state <= STATE_STP;
            snext <= STATE_IDLE;
            ulpi_data_out_buf <= 8'h00;
          end else begin
            state <= STATE_TX_LAST;
            snext <= 4'bx;
            ulpi_data_out_buf <= ulpi_data_out_buf;
          end
          reg_data <= 8'bx;
        end

        STATE_CHIRP_START: begin
          state <= STATE_WRITE_REGA;
          snext <= STATE_CHIRP_STARTK;
          ulpi_data_out_buf <= 8'h84;
          reg_data <= 8'b0_1_0_10_1_00;
        end
        STATE_CHIRP_STARTK: begin
          if (ulpi_nxt) begin
            state <= STATE_CHIRPK;
            ulpi_data_out_buf <= 8'h00;
          end else begin
            state <= STATE_CHIRP_STARTK;
            ulpi_data_out_buf <= 8'h40;
          end
          snext <= 4'bx;
          reg_data <= 8'bx;
        end
        STATE_CHIRPK: begin
          if (state_counter > CHIRP_K_TIME) begin
            state <= STATE_STP;
            snext <= STATE_CHIRPKJ;
          end else begin
            state <= state;
            snext <= 4'bx;
          end
          ulpi_data_out_buf <= 8'h00;
          reg_data <= 8'bx;
        end
        STATE_CHIRPKJ: begin
          if (chirp_kj_counter > 3 && state_counter > CHIRP_KJ_TIME) begin
            state <= STATE_WRITE_REGA;
            snext <= STATE_IDLE;
            ulpi_data_out_buf <= 8'h84;
            reg_data <= 8'b0_1_0_00_0_00;
          end else begin
            state <= state;
            snext <= 4'bx;
            ulpi_data_out_buf <= 8'h00;
            reg_data <= 8'bx;
          end
        end

        STATE_SWITCH_FSSTART: begin
          state <= STATE_WRITE_REGA;
          snext <= STATE_SWITCH_FS;
          reg_data <= 8'b0_1_0_00_1_01;
          ulpi_data_out_buf <= 8'h84;
        end
        STATE_SWITCH_FS: begin
          if (state_counter > SWITCH_TIME) begin
            if (usb_line_state == 2'b00 && HIGH_SPEED == 1) begin
              state <= STATE_CHIRP_START;
            end else begin
              state <= STATE_IDLE;
            end
          end else begin
            state <= state;
          end
          snext <= 4'bx;
          ulpi_data_out_buf <= 8'h00;
          reg_data <= 8'bx;
        end
      endcase
    end
  end


endmodule  // ulpi_encoder
