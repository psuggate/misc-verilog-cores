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

    // UTMI+ equivalent state-signals
    output [1:0] LineState,
    output [1:0] VbusState,
    output [1:0] RxEvent,

    // IOB-registered signals to the ULPI decoder
    output iob_dir_o,
    output iob_nxt_o,
    output [7:0] iob_dat_o,

    // Indicates the start-up & line states
    input  kj_start_i,
    output ls_host_se0_o,
    output ls_chirpk_o,
    output ls_chirpkj_o,

    // Useful timing-pulses
    output pulse_2_5us_o,
    output pulse_1_0ms_o,

    output phy_write_o,
    output phy_nopid_o,
    output phy_stop_o,
    input phy_done_i,
    output [7:0] phy_addr_o,
    output [7:0] phy_data_o
);


  // -- Constants -- //

`ifdef __icarus
  localparam integer SUSPEND_TIME = 4;  // ~3 ms
  localparam integer RESET_TIME = 4;  // ~3 ms
  localparam integer CHIRP_K_TIME = 7;  // ~1 ms
  localparam integer CHIRP_KJ_TIME = 7;  // ~2 us
  localparam integer SWITCH_TIME = 4;  // ~100 us
`else
  localparam integer SUSPEND_TIME = 190000;  // ~3 ms
  localparam integer RESET_TIME = 190000;  // ~3 ms
  localparam integer CHIRP_K_TIME = 66000;  // ~1 ms
  localparam integer CHIRP_KJ_TIME = 120;  // ~2 us
  localparam integer SWITCH_TIME = 6000;  // ~100 us
`endif

  localparam [3:0] ST_POWER_ON = 4'd0;
  localparam [3:0] ST_FS_START = 4'd1;
  localparam [3:0] ST_FS_NEXT0 = 4'd2;
  localparam [3:0] ST_FS_NEXT1 = 4'd3;
  localparam [3:0] ST_WAIT_SE0 = 4'd4;
  localparam [3:0] ST_CHIRP_K0 = 4'd5;
  localparam [3:0] ST_CHIRP_K1 = 4'd6;
  localparam [3:0] ST_CHIRP_K2 = 4'd7;
  localparam [3:0] ST_CHIRP_KJ = 4'd8;
  localparam [3:0] ST_HS_START = 4'd9;
  localparam [3:0] ST_HS_MODE = 4'd10;


  // -- State & Signals -- //

  reg [3:0] state, snext;
  reg dir_q, nxt_q, set_q, nop_q, stp_q;
  reg [7:0] dat_q, adr_q, val_q;
  reg rx_cmd_q, chirp_kj_q, chirp_k_q;

  reg pulse_2_5us, pulse_1_0ms;
  reg [7:0] count_2_5us;
  reg [8:0] count_1_0ms;
  wire clr_pulse_2_5us, clr_pulse_1_0ms, pulse_80us_w;


  // -- Output Assignments -- //

  assign iob_dir_o = dir_q;
  assign iob_nxt_o = nxt_q;
  assign iob_dat_o = dat_q;

  assign high_speed_o = state == ST_HS_MODE;
  assign usb_reset_o  = state == ST_HS_START;

  assign ls_host_se0_o = LineState == 2'b00;
  assign ls_chirpk_o = chirp_k_q;
  assign ls_chirpkj_o = chirp_kj_q;

  assign pulse_2_5us_o = pulse_2_5us;
  assign pulse_1_0ms_o = pulse_1_0ms;

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

  wire ls_changed;
  wire [1:0] LineStateW, VbusStateW, RxEventW, OpModeW;
  reg [1:0] LineStateQ, VbusStateQ, RxEventQ, OpModeQ;

  assign ls_changed = rx_cmd_q && (LineStateW != LineStateQ);

  assign LineStateW = dat_q[1:0];
  assign VbusStateW = dat_q[3:2];
  assign RxEventW = dat_q[5:4];

  // Todo: Gross !?
  assign LineState = rx_cmd_q ? LineStateW : LineStateQ;
  assign VbusState = rx_cmd_q ? VbusStateW : VbusStateQ;
  assign RxEvent = rx_cmd_q ? RxEventW : RxEventQ;

  // Pipeline the LineState changes, so that IOB registers can be used
  always @(posedge clock) begin
    rx_cmd_q <= dir_q && ulpi_dir && !ulpi_nxt;

    if (reset) begin
      LineStateQ <= 2'b01;  // 'J', apparently
      VbusStateQ <= 2'b00;
      RxEventQ   <= 2'b00;
    end else if (rx_cmd_q) begin
      LineStateQ <= LineStateW;
      VbusStateQ <= VbusStateW;
      RxEventQ   <= RxEventW;
    end
  end

  always @(posedge clock) begin
    chirp_k_q <= state == ST_CHIRP_K1;
  end


  // -- Timers for 2.5 us & 1.0 ms Pulses -- //

`ifdef __icarus
  // Because patience is for the weak
  localparam [7:0] COUNT_2_5_US = 7;
  localparam [8:0] COUNT_1_0_MS = 7;
`else
  localparam [7:0] COUNT_2_5_US = 149;
  localparam [8:0] COUNT_1_0_MS = 399;
`endif

  // todo ...
  assign clr_pulse_1_0ms = 1'b0;
  assign pulse_80us_w = pulse_2_5us && count_1_0ms[4:0] == 5'h10;

  // Start the 2.5 us wait, after SE0 during initialisation
  assign clr_pulse_2_5us = state == ST_POWER_ON && kj_start_i;

  // Pulse-signal & timer(-counter) for 2.5 us
  always @(posedge clock) begin
    if (reset) begin
      pulse_2_5us <= 1'b0;
      count_2_5us <= 8'd0;
    end else begin
      if (clr_pulse_2_5us || count_2_5us == COUNT_2_5_US) begin
        pulse_2_5us <= ~clr_pulse_2_5us;
        count_2_5us <= 8'd0;
      end else begin
        pulse_2_5us <= 1'b0;
        count_2_5us <= count_2_5us + 8'd1;
      end
    end
  end

  // Pulse-signal & timer(-counter) for 1.0 ms
  always @(posedge clock) begin
    if (reset) begin
      pulse_1_0ms <= 1'b0;
      count_1_0ms <= 9'd0;
    end else if (clr_pulse_1_0ms || pulse_2_5us) begin
      if (clr_pulse_1_0ms || count_1_0ms == COUNT_1_0_MS) begin
        pulse_1_0ms <= ~clr_pulse_1_0ms;
        count_1_0ms <= 9'd0;
      end else begin
        pulse_1_0ms <= 1'b0;
        count_1_0ms <= count_1_0ms + 9'd1;
      end
    end else begin
      pulse_1_0ms <= 1'b0;
      count_1_0ms <= count_1_0ms;
    end
  end


  // -- Main LineState and Start-Up FSM -- //

  reg kj_start_q, kj_valid_q, kj_ended_q;
  reg  [2:0] kj_count_q;
  wire [2:0] kj_cnext_w = kj_count_q + 3'd1;

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
   *    - On 'pulse_1_0ms', assert 'stp' for 1 cycle
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
    if (state == ST_CHIRP_KJ) begin
      // After the start of each J/K, wait at least 2.5 us before considering it
      // as a valid symbol.
      if (!kj_start_q && ls_changed) begin
        kj_start_q <= 1'b1;
        kj_valid_q <= 1'b0;
        kj_ended_q <= 1'b0;
      end else if (kj_start_q && pulse_2_5us && !kj_valid_q) begin
        kj_start_q <= 1'b0;
        kj_valid_q <= 1'b1;
        kj_count_q <= kj_cnext_w;
        kj_ended_q <= kj_cnext_w == 3'd6;
      end
    end else begin
      kj_start_q <= 1'b0;
      kj_valid_q <= 1'b0;
      kj_ended_q <= 1'b0;
      kj_count_q <= 3'd0;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      state      <= ST_POWER_ON;
      set_q      <= 1'b0;
      nop_q      <= 1'b0;
      stp_q      <= 1'b0;
      chirp_kj_q <= 1'b0;
    end else if (dir_q || ulpi_dir) begin
      set_q <= 1'b0;
    end else begin
      case (state)
        ST_POWER_ON: begin
          // state <= ST_FS_START;
          // {set_q, adr_q, val_q} <= {1'b1, 8'h8A, 8'd0};
          if (pulse_2_5us) begin
            state <= ST_FS_START;
            {set_q, adr_q, val_q} <= {1'b1, 8'h8A, 8'd0};
          end else begin
            state <= state;
            {set_q, adr_q, val_q} <= {1'b0, 8'd0, 8'd0};
          end
          chirp_kj_q <= 1'b0;
        end

        //
        //  Switch to FS-mode on start-up or reset
        ///
        ST_FS_START: begin
          if (phy_done_i) begin
            state <= ST_FS_NEXT0;
            {set_q, adr_q, val_q} <= {1'b1, 8'h84, 8'h45};
          end else begin
            set_q <= ulpi_nxt ? 1'b0 : 1'b1;
          end
        end

        ST_FS_NEXT0: begin
          if (phy_done_i) begin
            state <= ST_FS_NEXT1;
            set_q <= 1'b0;
          end else begin
            set_q <= ulpi_nxt ? 1'b0 : 1'b1;
          end
        end

        ST_FS_NEXT1: begin
          state <= LineState == 2'b00 ? ST_WAIT_SE0 : state;
          set_q <= 1'b0;
        end

        ST_WAIT_SE0: begin
          if (pulse_2_5us) begin
            // Set the Xcvrs to HS-mode
            state <= ST_CHIRP_K0;
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
          end else begin
            set_q <= ulpi_nxt ? 1'b0 : 1'b1;
          end
        end

        ST_CHIRP_K1: begin
          // todo: start timer when 'nxt' arrives ??
          // if (ulpi_nxt) begin
          if (pulse_1_0ms) begin
            state <= ST_CHIRP_K2;
            stp_q <= 1'b1;
          end
          nop_q <= 1'b0;
        end

        ST_CHIRP_K2: begin
          // Wait at least 1.0 ms
          // todo: issue stop, then wait for 'RX CMD' ('squelch')
          state <= LineState == 2'b00 ? ST_CHIRP_KJ : state;
          nop_q <= 1'b0;
          stp_q <= 1'b0;
        end

        //
        //  Attempt to handshake for HS-mode
        ///
        ST_CHIRP_KJ: begin
          state      <= kj_ended_q ? ST_HS_START : state;
          set_q      <= 1'b0;
          stp_q      <= 1'b0; // kj_ended_q ? 1'b1 : 1'b0;
          chirp_kj_q <= kj_start_q && pulse_2_5us && !kj_valid_q;
          {set_q, adr_q, val_q} <= {kj_ended_q, 8'h84, 8'h40};
        end

        ST_HS_START: begin
          stp_q <= 1'b0;
          if (phy_done_i) begin
            state <= ST_HS_MODE;
            set_q <= 1'b0;
          end else begin
            set_q <= ulpi_nxt ? 1'b0 : 1'b1;
          end
        end

        ST_HS_MODE: begin
          state      <= state;
          set_q      <= 1'b0;
          stp_q      <= 1'b0;
          chirp_kj_q <= 1'b0;
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
      ST_FS_NEXT0: dbg_state = "FS_NEXT0";
      ST_FS_NEXT1: dbg_state = "FS_NEXT1";
      ST_WAIT_SE0: dbg_state = "WAIT_SE0";
      ST_CHIRP_K0: dbg_state = "CHIRP_K0";
      ST_CHIRP_K1: dbg_state = "CHIRP_K1";
      ST_CHIRP_K2: dbg_state = "CHIRP_K2";
      ST_CHIRP_KJ: dbg_state = "CHIRP_KJ";
      ST_HS_START: dbg_state = "HS_START";
      ST_HS_MODE: dbg_state = "HS_MODE";
      default: dbg_state = "XXXX";
    endcase
  end

`endif


endmodule  // line_state
