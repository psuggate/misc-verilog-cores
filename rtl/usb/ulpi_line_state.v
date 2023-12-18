`timescale 1ns / 100ps
module ulpi_line_state #(
    parameter HIGH_SPEED = 1
) (
    input clock,
    input reset,

    // Raw FPGA IOB values from the ULPI PHY
    input ulpi_dir,
    input ulpi_nxt,
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
  localparam integer SUSPEND_TIME = 190;  // ~3 ms
  localparam integer RESET_TIME = 190;  // ~3 ms
  localparam integer CHIRP_K_TIME = 660;  // ~1 ms
  localparam integer CHIRP_KJ_TIME = 12;  // ~2 us
  localparam integer SWITCH_TIME = 60;  // ~100 us
`else
  localparam integer SUSPEND_TIME = 190000;  // ~3 ms
  localparam integer RESET_TIME = 190000;  // ~3 ms
  localparam integer CHIRP_K_TIME = 66000;  // ~1 ms
  localparam integer CHIRP_KJ_TIME = 120;  // ~2 us
  localparam integer SWITCH_TIME = 6000;  // ~100 us
`endif

  localparam [3:0]
	LX_INIT = 4'h0,
	LX_WAIT = 4'hf,
	LX_WRITE_REG = 4'h1,
	LX_RESET = 4'h2,
	LX_SUSPEND = 4'h3,
	LX_IDLE = 4'h4,
	LX_STOP = 4'h5,
	LX_CHIRP_START = 4'h6,
	LX_CHIRP_STARTK = 4'h7,
	LX_CHIRPK = 4'h8,
	LX_CHIRPKJ = 4'h9,
	LX_SWITCH_FSSTART = 4'ha,
	LX_SWITCH_FS = 4'hb;


  // -- State & Signals -- //

  reg [3:0] xinit, xnext;
  reg dir_q, nxt_q, set_q, stp_q;
  reg [7:0] adr_q, val_q;
  reg rx_cmd_q;
  reg [7:0] dat_q;

  reg hs_mode_q, usb_rst_q;


  // -- Output Assignments -- //

  assign iob_dir_o = dir_q;
  assign iob_nxt_o = nxt_q;
  assign iob_dat_o = dat_q;

  assign phy_write_o = set_q;
  assign phy_nopid_o = 1'b0;
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
      LineStateQ <= 2'b00;
      VbusStateQ <= 2'b00;
      RxEventQ   <= 2'b00;
    end else
    if (rx_cmd_q) begin
      LineStateQ <= LineStateW;
      VbusStateQ <= VbusStateW;
      RxEventQ   <= RxEventW;
    end
  end


  // -- Chirping & 'LineState' -- //

  reg [17:0] st_count;
  reg [2:0] kj_count;
  wire [17:0] st_cnext;
  wire [2:0] kj_cnext;
  wire ls_changed;

  assign st_cnext   = st_count + 18'd1;
  assign kj_cnext   = kj_count + 3'd1;

  assign ls_changed = rx_cmd_q && (LineStateW != LineStateQ);

  always @(posedge clock) begin
    if (reset || xinit != LX_CHIRPKJ) begin
      kj_count <= 3'd0;
    end else if (xinit == LX_CHIRPKJ && LineStateW == 2'b01 && ls_changed) begin
      kj_count <= kj_cnext;
    end else begin
      kj_count <= kj_count;
    end

    if (reset || xinit == LX_CHIRP_STARTK || xinit == LX_SWITCH_FSSTART || ls_changed) begin
      st_count <= 18'd0;
    end else begin
      st_count <= st_cnext;
    end
  end

  // Issuer of PHY STOP commands at the end of chirping //
  always @(posedge clock) begin
    if (reset) begin
      stp_q <= 1'b0;
    end else begin
      if (xinit == LX_CHIRPK && !phy_busy_i && st_count > CHIRP_K_TIME) begin
        stp_q <= 1'b1;
      end else if (phy_busy_i) begin
        stp_q <= 1'b0;
      end
    end
  end


  // -- PHY Operating Modes & Control Registers -- //

  always @(posedge clock) begin
    case (xinit)
      LX_SWITCH_FSSTART: hs_mode_q <= 1'b0;
      LX_CHIRPKJ: hs_mode_q <= 1'b1;
      default: hs_mode_q <= hs_mode_q;
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      usb_rst_q <= 1'b0;
    end else if (!dir_q && !ulpi_dir) begin
      if (xinit == LX_RESET) begin
        usb_rst_q <= 1'b1;
      end else if (xinit == LX_IDLE) begin
        usb_rst_q <= 1'b0;
      end else begin
        usb_rst_q <= usb_rst_q;
      end
    end else begin
      usb_rst_q <= usb_rst_q;
    end
  end


  // -- USB & PHY Line States -- //

  always @(posedge clock) begin
    if (reset || dir_q || ulpi_dir) begin
      {set_q, adr_q, val_q} <= {1'b0, 8'hx, 8'hx};
    end else begin
      case (xinit)
        // De-assert request after ACK
        LX_WRITE_REG: begin
          if (phy_busy_i) begin
            {set_q, adr_q, val_q} <= {1'b0, adr_q, val_q};
          end
        end

        LX_WAIT: begin
          if (phy_done_i) begin
            {set_q, adr_q, val_q} <= {1'b0, 8'hx, 8'hx};
          end
        end

        LX_CHIRP_START: begin
          // Wait for the PHY
          if (!phy_busy_i) begin
            set_q <= 1'b1;
            adr_q <= 8'h84;
            val_q <= 8'b0_1_0_10_1_00;
          end else begin
            {set_q, adr_q, val_q} <= {1'b0, 8'hx, 8'hx};
          end
        end

        LX_CHIRPKJ: begin
          if (kj_count > 3 && st_count > CHIRP_KJ_TIME) begin
            set_q <= 1'b1;
            adr_q <= 8'h84;
            val_q <= 8'b0_1_0_00_0_00;
          end else begin
            {set_q, adr_q, val_q} <= {1'b0, 8'hx, 8'hx};
          end
        end

        LX_SWITCH_FSSTART: begin
          set_q <= 1'b1;
          val_q <= 8'b0_1_0_00_1_01;
          adr_q <= 8'h84;
        end

        LX_INIT: {set_q, adr_q, val_q} <= {1'b1, 8'h8A, 8'h00};
        default: {set_q, adr_q, val_q} <= {1'b0, 8'hx, 8'hx};
      endcase
    end
  end


  // -- ULPI Initialisation FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      xinit <= LX_INIT;
      xnext <= 4'hx;
    end else if (dir_q || ulpi_dir) begin
      // We are not driving //
      xinit <= xinit;
      xnext <= 4'hx;
    end else begin
      // We are driving //
      case (xinit)
        default: begin  // LX_INIT
          xinit <= LX_WRITE_REG;
          xnext <= LX_SWITCH_FSSTART;
        end

        LX_WRITE_REG: begin
          // {xinit, xnext} <= phy_busy_i ? {xnext, 4'hx} : {xinit, xnext};
          xinit <= phy_busy_i ? LX_WAIT : xinit;
          xnext <= xnext;
          // if (phy_done_i) begin
          //   xinit <= xnext;
          //   xnext <= 4'hx;
          // end
        end

        LX_WAIT: begin
          {xinit, xnext} <= phy_done_i ? {xnext, 4'hx} : {xinit, xnext};
        end

        LX_RESET: begin
          if (HIGH_SPEED == 1) begin
            xinit <= hs_mode_q ? LX_SWITCH_FSSTART : LX_CHIRP_START;
          end else if (LineStateQ != 2'b00) begin
            xinit <= LX_IDLE;
          end else begin
            xinit <= xinit;
          end
          xnext <= 4'hx;
        end

        LX_SUSPEND: begin
          xinit <= LineStateQ != 2'b01 ? LX_IDLE : LX_SUSPEND;
          xnext <= 4'hx;
        end

        LX_IDLE: begin
          if (LineStateQ == 2'b00 && st_count > RESET_TIME) begin
            xinit <= LX_RESET;
          end else if (!hs_mode_q && LineStateQ == 2'b01 && st_count > SUSPEND_TIME) begin
            xinit <= LX_SUSPEND;
          end
          xnext <= 4'hx;
        end

        LX_STOP: begin
          {xinit, xnext} <= phy_busy_i ? {xnext, 4'hx} : {xinit, xnext};
        end

        LX_CHIRP_START: begin
          // Sets PHY function register: REG=04h, VAL=54h
          if (set_q && phy_busy_i) begin
            xinit <= LX_WRITE_REG;
            xnext <= LX_CHIRP_STARTK;
          end
        end

        LX_CHIRP_STARTK: begin
          xinit <= phy_busy_i ? LX_CHIRPK : xinit;
          xnext <= 4'hx;
        end

        LX_CHIRPK: begin
          if (st_count > CHIRP_K_TIME && !phy_busy_i) begin
            xinit <= LX_STOP;
            xnext <= LX_CHIRPKJ;
          end else begin
            xinit <= xinit;
            xnext <= 4'hx;
          end
        end

        LX_CHIRPKJ: begin
          if (kj_count > 3 && st_count > CHIRP_KJ_TIME) begin
            xinit <= LX_WRITE_REG;
            xnext <= LX_IDLE;
          end else begin
            xinit <= xinit;
            xnext <= 4'hx;
          end
        end

        LX_SWITCH_FSSTART: begin
          xinit <= LX_WRITE_REG;
          xnext <= LX_SWITCH_FS;
        end

        LX_SWITCH_FS: begin
          if (st_count > SWITCH_TIME) begin
            if (LineStateQ == 2'b00 && HIGH_SPEED == 1) begin
              xinit <= LX_CHIRP_START;
            end else begin
              xinit <= LX_IDLE;
            end
          end else begin
            xinit <= xinit;
          end
          xnext <= 4'hx;
        end
      endcase
    end
  end


endmodule  // ulpi_line_state
