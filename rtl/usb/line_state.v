`timescale 1ns / 100ps
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
    // output [1:0] OpMode,

    // IOB-registered signals to the ULPI decoder
    output iob_dir_o,
    output iob_nxt_o,
    output [7:0] iob_dat_o,

    // Signals for controlling the ULPI PHY
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
  localparam integer SUSPEND_TIME = 4;  // ~3 ms
  localparam integer RESET_TIME = 4;  // ~3 ms
  localparam integer CHIRP_K_TIME = 4;  // ~1 ms
  localparam integer CHIRP_KJ_TIME = 3;  // ~2 us
  localparam integer SWITCH_TIME = 4;  // ~100 us
`else
  localparam integer SUSPEND_TIME = 190000;  // ~3 ms
  localparam integer RESET_TIME = 190000;  // ~3 ms
  localparam integer CHIRP_K_TIME = 66000;  // ~1 ms
  localparam integer CHIRP_KJ_TIME = 120;  // ~2 us
  localparam integer SWITCH_TIME = 6000;  // ~100 us
`endif

  localparam [3:0]
	LX_POWER_ON = 4'h0,
	LX_ATTACH = 4'h1,
	LX_NORMAL = 4'h1,
	LX_WAIT = 4'hf,
	LX_WRITE_REG = 4'h1,
	LX_RESET = 4'h2,
	LX_SUSPEND = 4'h3,
	LX_RESUME = 4'h3,
	LX_IDLE = 4'h4,
	LX_STOP = 4'h5,
	LX_CHIRP_START = 4'h6,
	LX_CHIRP_STARTK = 4'h7,
	LX_CHIRPK = 4'h8,
	LX_CHIRPKJ = 4'h9,
	LX_SWITCH_FSSTART = 4'ha,
	LX_SWITCH_FS = 4'hb;


  // -- State & Signals -- //

  reg [3:0] state, snext;
  reg dir_q, nxt_q, set_q, stp_q, nop_q;
  reg [7:0] adr_q, val_q;
  reg rx_cmd_q;
  reg [7:0] dat_q;

  reg hs_mode_q, usb_rst_q;


  // -- Output Assignments -- //

  assign iob_dir_o = dir_q;
  assign iob_nxt_o = nxt_q;
  assign iob_dat_o = dat_q;

  assign phy_write_o = set_q;
  assign phy_nopid_o = nop_q;
  assign phy_stop_o = stp_q;
  assign phy_addr_o = adr_q;
  assign phy_data_o = val_q;

  assign high_speed_o = hs_mode_q;
  assign usb_reset_o = usb_rst_q;


  // -- IOB Registers -- //

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
    nxt_q <= ulpi_nxt;
    dat_q <= ulpi_data;
  end


  // -- USB Line State & PHY Events -- //

  wire [1:0] LineStateW, VbusStateW, RxEventW, OpModeW;
  reg [1:0] LineStateQ, VbusStateQ, RxEventQ, OpModeQ;

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
      LineStateQ <= 2'b01; // 'J', apparently
      VbusStateQ <= 2'b00;
      RxEventQ   <= 2'b00;
    end else if (rx_cmd_q) begin
      LineStateQ <= LineStateW;
      VbusStateQ <= VbusStateW;
      RxEventQ   <= RxEventW;
    end
  end


  // -- Line-State Signals -- //

  // todo: desirable ??
  wire se0_w = dir_q && ulpi_dir && LineState == 2'b00;


  // -- Timers for 2.5 us & 1.0 ms Pulses -- //

`ifdef __icarus
  // Because patience is for the weak
  localparam [7:0] COUNT_2_5_US = 3;
  localparam [8:0] COUNT_1_0_MS = 7;
`else
  localparam [7:0] COUNT_2_5_US = 149;
  localparam [8:0] COUNT_1_0_MS = 399;
`endif

  reg pulse_2_5us, pulse_1_0ms;
  reg [7:0] count_2_5us;
  reg [8:0] count_1_0ms;
  wire clr_pulse_2_5us, clr_pulse_1_0ms, pulse_80us_w;

  // Start the 2.5 us wait, after SE0 during initialisation
  assign clr_pulse_2_5us = state == ST_ATTACH && rx_cmd_q && LineStateW == 2'b00;

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

  // Nein blyat.
  assign clr_pulse_1_0ms = 1'b0;
  assign pulse_80us_w = pulse_2_5us && count_1_0ms[4:0] == 5'h10;

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

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_POWER_ON;
      set_q <= 1'b0;
      stp_q <= 1'b0;
      nop_q <= 1'b0;
    end else begin
      case (state)
        ST_POWER_ON: begin
          // Set the ULPI PHY to FS-mode, in order to listen to host signals
          state <= ST_WR_REGA;
          snext <= ST_FSSTART;

          set_q <= 1'b1;
          adr_q <= 8'h8A;
          val_q <= 8'h00;
        end

        //
        //  Switch to FS-mode prior to chirping
        ///
        ST_FSSTART: begin
          // Switch to FS-mode, and then wait for the host
          state <= ST_WR_REGA;
          snext <= ST_FSRESET;

          set_q <= 1'b1;
          adr_q <= 8'h84;
          val_q <= 8'h45;
        end

        ST_FSRESET: begin
          // Issue RESET to the USB core/function, while transceivers start
          state <= pulse_80us_w ? ST_FSWITCH : rx_cmd_q && LineStateW == 2'b00 ? ST_STARTUP : state;
        end

        ST_FSWITCH: begin
          // Wait for the transceivers to switch to FS-mode, and then listen for
          // 'SE0' to be signaled
          state <= rx_cmd_q && LineStateW == 2'b00 ? ST_STARTUP : state;
        end

        ST_STARTUP: begin
          // Wait for the host to hold SE0 for atleast 2.5 us, then continue
          // start-up sequence (peripheral emits 'K' chirp)
          state <= pulse_2_5us ? ST_WR_REGA : state;
          snext <= ST_CHIRPK0;

          set_q <= 1'b1;
          adr_q <= 8'h84;
          val_q <= 8'h54;
        end

        //
        //  Negotiate HS-mode via Chirping
        ///
        ST_CHIRPK0: begin
          // Send a 'NO PID' command to the PHY to initiate the 'K'-chirp
          state <= phy_busy_i ? ST_CHIRPK1 : state;
          nop_q <= 1'b1;
        end

        ST_CHIRPK1: begin
          // Wait for at least 1.0 ms, and for the PHY to accept, before issuing
          // chirp-'STOP'
          state <= pulse_1_0ms && ulpi_nxt ? ST_CHIRPK2 : state;
          nop_q <= 1'b0;
          stp_q <= pulse_1_0ms && ulpi_nxt;
        end

        ST_CHIRPK2: begin
          // Wait for the PHY to signal 'squelch', then switch to listening to
          // the host K/J chirps
          state <= rx_cmd_q ? ST_CHIRPKJ : state;
          stp_q <= 1'b0;
        end

        ST_CHIRPKJ: begin
          // Wait for the host to chirp 6x (K-J-K-J-K-J), then switch the PHY
          // transceivers to HS-mode
          state <= kj_count == 3 && pulse_2_5us ? ST_WR_REGA : state;
          snext <= ST_HS_MODE;

          set_q <= 1'b1;
          adr_q <= 8'h84;
          val_q <= 8'h40;
        end

        ST_HS_MODE: begin
          // Done (after 'squelch')
          state <= state;
        end

        //
        //  Write to a ULPI PHY register
        ///
        ST_WR_REGA: state <= ulpi_nxt ? ST_WR_REGD : state;
        ST_WR_REGD: state <= ulpi_nxt ? snext : state;

        // default: begin
        //   state <= ST_RESET;
        // end

      endcase
    end
  end


endmodule // line_state
