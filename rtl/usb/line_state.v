`timescale 1ns / 100ps
/**
 * Monitors the USB 'LineState', and provides the signals required for the ULPI
 * PHY to be started-up and brought into the desired operating mode.
 */
module line_state #(
    parameter HIGH_SPEED = 1
) (
    input clock,
    input reset,

    // Raw FPGA IOB values from the ULPI PHY
    input ulpi_dir,
    input ulpi_nxt,
    input ulpi_stp,
    input [7:0] ulpi_data,

    // USB-core status and control-signals
    output high_speed_o,
    output usb_reset_o,
    output ls_changed_o,
    output ulpi_rx_cmd_o,
    output ulpi_idle_o,
    output [3:0] phy_state_o,

    // UTMI+ equivalent state-signals
    output [1:0] LineState,
    output [1:0] VbusState,
    output [1:0] RxEvent,

    // IOB-registered signals to the ULPI decoder
    output iob_dir_o,
    output iob_nxt_o,
    output [7:0] iob_dat_o,

    // Useful timing-pulses
    output pulse_2_5us_o,
    output pulse_1_0ms_o,

    output phy_write_o,
    output phy_nopid_o,
    output phy_stop_o,
    input phy_busy_i,
    input phy_done_i,
    output [7:0] phy_addr_o,
    output [7:0] phy_data_o
);


  // -- Constants -- //

`ifdef __icarus
  localparam [7:0] COUNT_2_5_US = 5;
  localparam [5:0] COUNT_100_US = 6;
  localparam [8:0] COUNT_1_0_MS = 7;
`else
  localparam [7:0] COUNT_2_5_US = 149;
  localparam [5:0] COUNT_100_US = 39;
  localparam [8:0] COUNT_1_0_MS = 399;
`endif

  localparam [3:0] ST_POWER_ON = 4'd0;
  localparam [3:0] ST_FS_START = 4'd1;
  localparam [3:0] ST_FS_LSSE0 = 4'd2;
  localparam [3:0] ST_WAIT_SE0 = 4'd3;
  localparam [3:0] ST_CHIRP_K0 = 4'd4;
  localparam [3:0] ST_CHIRP_K1 = 4'd5;
  localparam [3:0] ST_CHIRP_K2 = 4'd6;
  localparam [3:0] ST_CHIRP_KJ = 4'd7;
  localparam [3:0] ST_HS_START = 4'd8;
  localparam [3:0] ST_IDLE = 4'd9;
  localparam [3:0] ST_SUSPEND = 4'd10;
  localparam [3:0] ST_RESUME = 4'd11;
  localparam [3:0] ST_RESET = 4'd12;


  // -- State & Signals -- //

  reg [3:0] state;
  reg dir_q, nxt_q, set_q, nop_q, stp_q, hse_q, rst_q;
  reg [7:0] dat_q, adr_q, val_q;
  reg rx_cmd_q, hs_mode_q;
  reg new_ls_q, is_idle_q;

  // Pulse-signal & timer(-counter) for 2.5 us, and for a constant line-state
  reg pulse_2_5us, ls_pulse_1_0ms, ls_pulse_3_0ms, ls_pulse_21_ms, pulse_100us;
  reg [7:0] count_2_5us;
  reg [5:0] count_100us;
  reg [8:0] ls_count_1_0ms;
  reg [1:0] ls_count_3_0ms;
  reg [2:0] ls_count_21_ms;


  // -- Output Assignments -- //

  assign iob_dir_o = dir_q;
  assign iob_nxt_o = nxt_q;
  assign iob_dat_o = dat_q;

  assign high_speed_o = hs_mode_q;
  assign usb_reset_o = rst_q;
  assign ls_changed_o = new_ls_q;
  assign ulpi_rx_cmd_o = rx_cmd_q;
  assign ulpi_idle_o = is_idle_q;
  assign phy_state_o = state;

  assign pulse_2_5us_o = pulse_2_5us;
  assign pulse_1_0ms_o = ls_pulse_1_0ms;

  assign phy_write_o = set_q;
  assign phy_nopid_o = nop_q;
  assign phy_stop_o = stp_q;
  assign phy_addr_o = adr_q;
  assign phy_data_o = val_q;


  // -- IOB Registers -- //

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
    nxt_q <= ulpi_nxt;
    dat_q <= ulpi_data;
  end


  // -- USB Line State & PHY Events -- //

  wire ls_changed, rx_cmd_w, new_ls_w;
  wire [1:0] LineStateW, VbusStateW, RxEventW, OpModeW;
  reg [1:0] LineStateQ, VbusStateQ, RxEventQ, OpModeQ;

  assign rx_cmd_w = dir_q && ulpi_dir && !ulpi_nxt;
  assign new_ls_w = rx_cmd_q && (LineStateW != LineStateQ);
  assign ls_changed = new_ls_q;  // rx_cmd_q && (LineStateW != LineStateQ);

  assign LineStateW = dat_q[1:0];
  assign VbusStateW = dat_q[3:2];
  assign RxEventW = dat_q[5:4];

  assign LineState = LineStateQ;
  assign VbusState = VbusStateQ;
  assign RxEvent = RxEventQ;

  // Pipeline the LineState changes, so that IOB registers can be used
  always @(posedge clock) begin
    rx_cmd_q  <= rx_cmd_w;
    new_ls_q  <= new_ls_w;
    is_idle_q <= !reset && hse_q && state == ST_IDLE;

    if (reset || state == ST_FS_START) begin
      hs_mode_q <= 1'b0;
    end else if (state == ST_IDLE && hse_q) begin
      hs_mode_q <= 1'b1;
    end

    if (reset) begin
      // LineStateQ <= 2'b01;  // 'J', apparently
      LineStateQ <= 2'b10;  // 'K', apparently
      VbusStateQ <= 2'b00;
      RxEventQ   <= 2'b00;
    end else if (rx_cmd_q) begin
      LineStateQ <= LineStateW;
      VbusStateQ <= VbusStateW;
      RxEventQ   <= RxEventW;
    end
  end

  // State-output registers
  always @(posedge clock) begin
    if (reset) begin
      rst_q <= 1'b0;
    end else begin
      if (state == ST_RESET) begin
        rst_q <= 1'b1;
      end else if (state == ST_IDLE) begin
        rst_q <= 1'b0;
      end
    end
  end


  // -- Timers for 2.5 us & 1.0 ms Pulses -- //

  always @(posedge clock) begin
    // if (reset || ls_changed) begin
    if (reset) begin
      pulse_2_5us <= 1'b0;
      count_2_5us <= 8'd0;
    end else begin
      if (count_2_5us == COUNT_2_5_US) begin
        pulse_2_5us <= 1'b1;
        count_2_5us <= 8'd0;
      end else begin
        pulse_2_5us <= 1'b0;
        count_2_5us <= count_2_5us + 8'd1;
      end
    end
  end

  // Pulse-signal (/timer) for 100 us duration
  always @(posedge clock) begin
    if (reset || state == ST_FS_START && phy_done_i) begin
      pulse_100us <= 1'b0;
      count_100us <= 6'd0;
    end else if (pulse_2_5us) begin
      if (count_100us == COUNT_100_US) begin
        pulse_100us <= 1'b1;
        count_100us <= 6'd0;
      end else begin
        pulse_100us <= 1'b0;
        count_100us <= count_100us + 6'd1;
      end
    end else begin
      pulse_100us <= 1'b0;
    end
  end

  // Pulse-signal & timer(-counter) for 1.0 ms, and for a constant line-state
  always @(posedge clock) begin
    if (reset || ls_changed) begin
      ls_pulse_1_0ms <= 1'b0;
      ls_count_1_0ms <= 9'd0;
    end else if (pulse_2_5us) begin
      if (ls_count_1_0ms == COUNT_1_0_MS) begin
        ls_pulse_1_0ms <= 1'b1;
        ls_count_1_0ms <= 9'd0;
      end else begin
        ls_pulse_1_0ms <= 1'b0;
        ls_count_1_0ms <= ls_count_1_0ms + 9'd1;
      end
    end else begin
      ls_pulse_1_0ms <= 1'b0;
    end
  end

  // Pulse-signal (/timer) for a 3.0 ms duration and constant line-state
  always @(posedge clock) begin
    if (reset || ls_changed) begin
      ls_pulse_3_0ms <= 1'b0;
      ls_count_3_0ms <= 2'd0;
    end else if (ls_pulse_1_0ms) begin
      if (ls_count_3_0ms == 2'd2) begin
        ls_pulse_3_0ms <= 1'b1;
        ls_count_3_0ms <= 2'd0;
      end else begin
        ls_pulse_3_0ms <= 1'b0;
        ls_count_3_0ms <= ls_count_3_0ms + 2'd1;
      end
    end else begin
      ls_pulse_3_0ms <= 1'b0;
    end
  end

  // Pulse-signal (/timer) for 21 ms duration and constant line-state
  always @(posedge clock) begin
    if (reset || ls_changed) begin
      ls_pulse_21_ms <= 1'b0;
      ls_count_21_ms <= 2'd0;
    end else if (ls_pulse_3_0ms) begin
      if (ls_count_21_ms == 3'd6) begin
        ls_pulse_21_ms <= 1'b1;
        ls_count_21_ms <= 3'd0;
      end else begin
        ls_pulse_21_ms <= 1'b0;
        ls_count_21_ms <= ls_count_21_ms + 3'd1;
      end
    end else begin
      ls_pulse_21_ms <= 1'b0;
    end
  end


  // -- Speed-neogiation LineState and Chirp-control -- //

  reg kj_valid_q, kj_ended_q;
  reg  [2:0] kj_count_q;
  wire [2:0] kj_cnext_w = kj_count_q + 3'd1;

  always @(posedge clock) begin
    if (state == ST_CHIRP_KJ) begin
      // After the start of each J/K, wait at least 2.5 us before considering it
      // as a valid symbol.
      if (pulse_2_5us) begin
        kj_valid_q <= 1'b1;
      end else if (new_ls_q) begin
        kj_valid_q <= 1'b0;
      end

      if (new_ls_q && LineState == 2'b01) begin
        kj_count_q <= kj_cnext_w;
        kj_ended_q <= kj_ended_q || kj_cnext_w == 3'd3;
      end
    end else begin
      kj_valid_q <= 1'b0;
      kj_ended_q <= 1'b0;
      kj_count_q <= 3'd0;
    end
  end


  // -- Main USB ULPI PHY LineState FSM -- //

  /**
   * Initialisation sequence:
   *  + Set to (normal) FS-mode:
   *    - WRITE REGISTER ADDRESS (0x8A)
   *    - WRITE REGISTER VALUE   (0x00)
   *    - WRITE REGISTER ADDRESS (0x84)
   *    - WRITE REGISTER VALUE   (0x45)
   *  + Wait for SE0 ('dir' for 'RX CMD'):
   *    - Clear 2.5 us timer on 'LineState == 2'b00'
   *    - Next-state on 'pulse_2_5us'
   *  + Set to (chirp) HS-mode:
   *    - WRITE REGISTER ADDRESS (0x84)
   *    - WRITE REGISTER VALUE   (0x54)
   *  + Start chirp-K:
   *    - Issue NOPID            (0x40)
   *    - Clear 1.0 ms timer on 'nxt'
   *    - On 'ls_pulse_1_0ms', assert 'stp' for 1 cycle
   *  + Wait for 'squelch' LineState (not required ??)
   *  + Receive K-J-K-J-K-J:
   *    - Rx K for > 2.5 us
   *    - Rx J for > 2.5 us
   *    - ...
   *  + Set to normal (HS-mode):
   *    - WRITE REGISTER ADDRESS (0x84)
   *    - WRITE REGISTER VALUE   (0x40)
   *  + Wait for 'squelch' ('LineState == 2'b00')
   * 
   * During this sequence, issue a 'reset' to the USB core.
   */
  always @(posedge clock) begin
    if (reset) begin
      state <= ST_POWER_ON;
      hse_q <= 1'b0;
      set_q <= 1'b0;
      nop_q <= 1'b0;
      stp_q <= 1'b0;
    end else if (dir_q || ulpi_dir) begin
      set_q <= 1'b0;
    end else begin
      case (state)
        ST_POWER_ON: begin
          if (phy_done_i) begin
            state <= ST_FS_START;
            {set_q, adr_q, val_q} <= {1'b0, 8'd0, 8'd0};
          end else begin
            {set_q, adr_q, val_q} <= {1'b1, 8'h8A, 8'd0};
          end
          // state <= phy_busy_i ? ST_FS_START : state;
          // {set_q, adr_q, val_q} <= {1'b1, 8'h8A, 8'd0};
        end

        ST_IDLE: begin
          if (ls_pulse_3_0ms && LineState == 2'b00) begin
            state <= ST_RESET;
          end else if (ls_pulse_3_0ms && LineState == 2'b01) begin
            state <= ST_SUSPEND;
          end
        end

        ST_RESET: begin
          state <= pulse_2_5us ? ST_FS_START : state;
          // todo: ...
        end

        ST_SUSPEND: begin
          // todo: ...
          if (LineState != 2'b01) begin
            state <= ST_IDLE;
          end
          // if (dir_q && LineState != 2'b10 && ls_pulse_21_ms) begin
          //   stp_q <= 1'b1;
          //   state <= ST_RESUME;
          // end
        end

        ST_RESUME: begin
          // todo: assert & hold 'stp' ...
          if (phy_done_i) begin
            state <= ST_IDLE;
            {set_q, adr_q, val_q} <= {1'b0, 8'd0, 8'd0};
          end else begin
            // Set the Xcvrs to HS-mode
            hse_q <= 1'b1;
            {set_q, adr_q, val_q} <= {1'b1, 8'h84, 8'h40};
          end
        end


        //
        //  Switch to FS-mode on start-up, reset, or suspend
        ///
        ST_FS_START: begin
          hse_q <= 1'b0;
          if (phy_done_i) begin
            state <= ST_FS_LSSE0;
            {set_q, adr_q, val_q} <= {1'b0, 8'd0, 8'd0};
          end else begin
            {set_q, adr_q, val_q} <= {1'b1, 8'h84, 8'h45};
          end
        end

        ST_FS_LSSE0: begin
          state <= LineState == 2'b00 ? ST_WAIT_SE0 : pulse_100us ? ST_IDLE : state;
          set_q <= 1'b0;
        end

        ST_WAIT_SE0: begin
          if (ls_changed) begin
            state <= ST_FS_LSSE0;
            set_q <= 1'b0;
          end else if (pulse_2_5us) begin
            // Set the Xcvrs to HS-mode
            state <= ST_CHIRP_K0;
            hse_q <= 1'b1;
            {set_q, adr_q, val_q} <= {1'b1, 8'h84, 8'h54};
          end else begin
            set_q <= 1'b0;
          end
        end

        ST_CHIRP_K0: begin
          if (phy_done_i) begin
            // Issue 'NO PID' command to start the 'K'-chirp
            state <= ST_CHIRP_K1;
            set_q <= 1'b0;  // todo: issue 'NO PID' here ??
            nop_q <= 1'b1;
          end
        end

        ST_CHIRP_K1: begin
          // todo: start timer when 'nxt' arrives ??
          if (ls_pulse_1_0ms) begin
            state <= ST_CHIRP_K2;
            stp_q <= 1'b1;
          end
          if (phy_done_i) begin
            nop_q <= 1'b0;
          end
        end

        ST_CHIRP_K2: begin
          // Wait at least 1.0 ms
          // todo: issue stop, then wait for 'RX CMD' ('squelch')
          nop_q <= 1'b0;
          stp_q <= 1'b0;
          state <= ST_CHIRP_KJ;
        end

        //
        //  Attempt to handshake for HS-mode
        ///
        ST_CHIRP_KJ: begin
          if (kj_ended_q && kj_valid_q) begin
            state <= ST_HS_START;
          end
          stp_q <= 1'b0;
        end

        ST_HS_START: begin
          if (phy_done_i) begin
            state <= ST_IDLE;
            {set_q, adr_q, val_q} <= {1'b0, 8'd0, 8'd0};
          end else begin
            hse_q <= 1'b1;
            {set_q, adr_q, val_q} <= {1'b1, 8'h84, 8'h40};
          end
        end
      endcase
    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  reg [95:0] dbg_state;

  always @* begin
    case (state)
      ST_POWER_ON: dbg_state = "POWER_ON";
      ST_FS_START: dbg_state = "FS_START";
      ST_FS_LSSE0: dbg_state = "FS_LSSE0";
      ST_WAIT_SE0: dbg_state = "WAIT_SE0";
      ST_CHIRP_K0: dbg_state = "CHIRP_K0";
      ST_CHIRP_K1: dbg_state = "CHIRP_K1";
      ST_CHIRP_K2: dbg_state = "CHIRP_K2";
      ST_CHIRP_KJ: dbg_state = "CHIRP_KJ";
      ST_HS_START: dbg_state = "HS_START";
      ST_RESET: dbg_state = "RESET";
      ST_SUSPEND: dbg_state = "SUSPEND";
      ST_RESUME: dbg_state = "RESUME";
      ST_IDLE: dbg_state = "IDLE";
      default: dbg_state = "XXXX";
    endcase
  end

`endif


endmodule  // line_state
