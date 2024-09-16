`timescale 1ns / 100ps
/**
 * Assembles USB packets in the format required by the ULPI PHY.
 *
 * Note(s):
 *  - the 's_tuser' signal contains the USB PID, and is sampled when 's_tvalid'
 *    asserts;
 *  - handshakes are sent using 'hsk_send_i' and 's_tuser' for the PID, and hold
 *    'hsk_send_i' high at least until 'usb_busy_o' asserts, but must be de-
 *    asserted before the end of 'usb_done_o';
 *  - a ZDP is sent using 's_tvalid = s_tlast = 1, s_tkeep = 0';
 *
 * Todo:
 *  - after a packet is sent, only strobe (HI) 'usb_done_o' when EOP has been
 *    confirmed (via RX CMD, or EOP-elapsed timer) !?
 *  - fails with LENGTH == 1 packets (the packet sends but then the encoder
 *    locks-up) !!
 */
module ulpi_encoder (
    input clock,
    input reset,

    input high_speed_i,
    output encode_idle_o,
    output [9:0] enc_state_o,

    input [1:0] LineState,
    input [1:0] VbusState,

    // Signals for controlling the ULPI PHY
    input phy_write_i,
    input phy_nopid_i,
    input phy_stop_i,
    output phy_busy_o,
    output phy_done_o,
    input [7:0] phy_addr_i,
    input [7:0] phy_data_i,

    input  hsk_send_i,
    output hsk_done_o,
    output usb_busy_o,
    output usb_done_o,

    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [3:0] s_tuser,  // USB PID
    input [7:0] s_tdata,

    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    output [7:0] ulpi_data
);

  // -- Definitions -- //

  `include "usb_defs.vh"


  // -- Constants -- //

  // FSM states
  localparam [9:0] TX_IDLE = 10'h001;
  localparam [9:0] TX_XPID = 10'h002;
  localparam [9:0] TX_DATA = 10'h004;
  localparam [9:0] TX_CRC0 = 10'h008;
  localparam [9:0] TX_CRC1 = 10'h010;
  localparam [9:0] TX_LAST = 10'h020;
  localparam [9:0] TX_DONE = 10'h040;
  localparam [9:0] TX_INIT = 10'h080;
  localparam [9:0] TX_REGW = 10'h100;
  localparam [9:0] TX_STOP = 10'h200;

  localparam [1:0] LS_EOP = 2'b00;


  // -- Signals & State -- //

  reg [9:0] xsend, xsend_q;
  reg dir_q, stp_q;
  reg phy_done_q, hsk_done_q, usb_done_q;

  // Transmit datapath MUX signals
  wire [1:0] mux_sel_w;
  wire [7:0] usb_pid_w, usb_dat_w, axi_dat_w, crc_dat_w, phy_dat_w, ulpi_dat_w;
  wire sready_w, tready_w;

  // Note: combinational
  reg svalid, sready, slast, tvalid, tlast;
  reg [7:0] sdata, tdata;

  wire mvalid_w, mready_w, mlast_w;
  wire [7:0] mdata_w;


  // -- I/O & Signal Assignments -- //

  // todo: check that this encodes correctly (as 'xsend[0]') !?
  assign encode_idle_o = xsend == TX_IDLE;
  assign enc_state_o = xsend_q;

  assign usb_busy_o = xsend != TX_IDLE;
  assign usb_done_o = usb_done_q;
  assign hsk_done_o = hsk_done_q;

  assign s_tready = sready;

  assign usb_pid_w = {2'b01, 2'b00, s_tuser};


  // -- ULPI Initialisation FSM -- //

  // Signals for sending initialisation commands & settings to the PHY.
  assign phy_busy_o = xsend != TX_IDLE && xsend != TX_DONE;
  assign phy_done_o = phy_done_q;

  always @(posedge clock) begin
    xsend_q <= xsend;

    phy_done_q <= xsend == TX_INIT && phy_nopid_i && !phy_done_q ||
                  xsend == TX_STOP && !phy_done_q && !phy_stop_i;
    hsk_done_q <= xsend == TX_STOP && hsk_send_i;
    usb_done_q <= xsend == TX_DONE && ulpi_stp && !hsk_send_i;
  end

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
    stp_q <= ulpi_stp;
  end


  // -- Tx data CRC Calculation -- //

  reg  [15:0] crc16_q;
  wire [15:0] crc16_nw;

  genvar ii;
  generate
    for (ii = 0; ii < 16; ii++) begin : g_crc16_revneg
      assign crc16_nw[ii] = ~crc16_q[15-ii];
    end  // g_crc16_revneg
  endgenerate

  always @(posedge clock) begin
    if (reset || xsend == TX_DONE) begin
      crc16_q <= 16'hffff;
    end else if (s_tvalid && s_tready && s_tkeep) begin
      crc16_q <= crc16(s_tdata, crc16_q);
    end
  end


  // -- ULPI Encoder FSM -- //

  reg end_q;

  always @(posedge clock) begin
    if (reset) begin
      end_q <= 1'b0;
    end else begin
      if (s_tvalid && s_tready && (!s_tkeep || s_tlast)) begin
        end_q <= 1'b1;
      end else if (xsend == TX_DONE) begin
        end_q <= 1'b0;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      xsend <= TX_IDLE;
    end else if (dir_q || ulpi_dir) begin
      // Todo: refactor to make a more efficient circuit
      xsend <= xsend == TX_DONE && LineState == 2'b00 ? TX_IDLE : xsend;
      // xsend <= xsend;
    end else begin
      case (xsend)
        default: begin  // TX_IDLE
          if (!sready_w) begin
            // Busy
            xsend <= TX_IDLE;
          end else if (!high_speed_i) begin
            // Need to negotiate HS-mode
            xsend <= phy_write_i && tready_w || phy_nopid_i ? TX_INIT :
                     phy_stop_i ? TX_STOP : TX_IDLE;
          end else begin
            xsend <= hsk_send_i || s_tvalid ? TX_XPID : TX_IDLE;
          end
        end

        TX_XPID: begin
          // Output PID has been accepted? If so, we can receive another byte.
          if (mvalid_w && hsk_send_i) begin
            xsend <= TX_STOP;
            // end else if (end_q || s_tvalid && s_tready && s_tlast) begin
          end else if (end_q) begin
            xsend <= TX_CRC0;
          end else if (mvalid_w) begin
            xsend <= TX_DATA;
          end
        end

        TX_DATA: begin
          // Continue transferring the packet data
          xsend <= s_tvalid && !s_tkeep && sready_w ? TX_CRC1 :
                   s_tlast && (sready_w || !sready_w && tvalid && tready_w) ? TX_CRC0 : xsend;
        end

        TX_CRC0: begin
          // Send 1st CRC16 byte
          xsend <= svalid && sready_w ? TX_CRC1 : xsend;
        end

        TX_CRC1: begin
          // Send 2nd CRC16 byte
          xsend <= svalid && sready_w ? TX_LAST : xsend;
        end

        TX_LAST: begin
          // Send 2nd (and last) CRC16 byte
          xsend <= slast && sready_w ? TX_DONE : xsend;
        end

        TX_DONE: begin
          // Wait for the PHY to signal that the USB LineState represents End-of
          // -Packet (EOP), indicating that the packet has been sent
          //
          // Todo:
          //  - the USB 2.0 spec. also gives a tick-count until the packet is
          //    considered to be sent ??
          //  - should wait for the current 'LineState' from the ULPI decoder
          //    module, via 'RX CMD', as the USB3317C datasheet states that an
          //    'RX CMD' follows every transmission (see pp.40) ??
          //
          xsend <= (!ulpi_stp && stp_q) || LineState == 2'b00 ? TX_IDLE : xsend;
        end

        //
        //  Until the PHY has been configured, respond to the commands from the
        //  'ulpi_line_state' module.
        ///
        TX_INIT: begin
          xsend <= phy_write_i && mvalid_w ? TX_REGW : phy_nopid_i && mvalid_w ? TX_IDLE : xsend;
        end

        TX_REGW: begin
          // Write to a PHY register
          xsend <= ulpi_nxt ? TX_STOP : xsend;
        end

        TX_STOP: begin
          // Wait for the PHY to accept a 'ulpi_data' value
          xsend <= phy_stop_i ? xsend : TX_DONE;
        end
      endcase
    end
  end


  // -- ULPI Data-Out MUX -- //

  //
  // ULPI output registers using an AXI-style skid-buffer, so that PHY commands
  // and AXI overruns can be easily handled.
  //
  always @* begin
    // Source -> ULPI stream
    svalid = 1'b0;
    sready = 1'b0;
    slast  = 1'b0;
    sdata  = 8'd0;
    // Temp-reg. -> ULPI stream
    tvalid = 1'b0;
    tlast  = 1'b0;
    tdata  = 8'd0;

    if (!ulpi_dir && !dir_q) begin
      case (xsend)
        TX_IDLE: begin
          if (s_tvalid && sready_w && s_tkeep) begin
            svalid = 1'b1;
            sready = 1'b1;
            sdata  = usb_pid_w;
            tvalid = 1'b1;
            // tlast  = s_tlast;
            tdata  = s_tdata;
          end
        end

        //
        //  USB Packet Transmit
        ///
        TX_XPID: begin
          // Note: needs to be able to "resume," after being interrupted by the
          //   ULPI PHY (before the Link has sent the first 'PID' byte)
          svalid = hsk_send_i || !mvalid_w || mready_w && s_tvalid && s_tkeep;
          //
          // -- TODO !!
          // sready = sready_w && mvalid_w;
          sready = sready_w && (!mvalid_w || mready_w);
          //
          sdata  = mvalid_w && mready_w ? s_tdata : usb_pid_w;
          if (hsk_send_i) begin
            // Load the temp-reg. with the "stop" value, for USB handshake
            // packets
            tvalid = 1'b1;
            tlast  = 1'b1;
          end
        end
        TX_DATA: begin
          svalid = sready_w;
          sready = sready_w;
          sdata  = s_tvalid && s_tkeep ? s_tdata : crc16_nw[7:0];
        end
        TX_CRC0: begin
          svalid = 1'b1;
          // svalid = sready_w;
          sready = s_tvalid && !s_tkeep;
          sdata  = crc16_nw[7:0];
        end
        TX_CRC1: begin
          svalid = 1'b1;
          // svalid = sready_w;
          sready = s_tvalid && !s_tkeep;
          sdata  = crc16_nw[15:8];
        end
        TX_LAST: begin
          svalid = 1'b1;
          // svalid = sready_w;
          sready = s_tvalid && !s_tkeep;
          slast  = 1'b1;
        end

        //
        //  Initialisation & Reset
        ///
        TX_INIT: begin
          svalid = phy_write_i || phy_nopid_i || phy_stop_i;
          slast  = phy_stop_i;
          sdata  = phy_write_i ? phy_addr_i : phy_nopid_i ? 8'h40 : 8'd0;
          tvalid = phy_write_i || phy_nopid_i;
          tlast  = 1'b0;
          tdata  = phy_write_i ? phy_data_i : 8'd0;
        end
        TX_REGW: begin
        end

        //
        //  Finish Transaction
        ///
        TX_STOP: begin
          svalid = 1'b1;
          slast  = 1'b1;
        end
        TX_DONE: begin
        end
      endcase
    end
  end


  // -- Skid Register with Loadable, Overflow Register -- //

  assign mready_w  = ulpi_nxt;
  assign ulpi_stp  = mlast_w;
  assign ulpi_data = !ulpi_dir ? mdata_w : 8'bz;

  // Load the 'temp. reg.' of the skid-buffer:
  //  - with ULPI PHY register value, when writing to a ULPI PHY register;
  //  - with '0x40' when issuing a 'NO PID' command; e.g., to initiate a K-chirp
  //    during High-Speed negotiation;
  //  - with '0x00' when issuing a USB handshake packet;
  //  - with 'data[0]' (and data-overflows due to flow-control), when performing
  //    USB data 'IN' transactions;

  skid_loader #(
      .RESET_TDATA(1),
      .RESET_VALUE(8'd0),
      .WIDTH(8),
      .BYPASS(0),
      .LOADER(1)
  ) U_SKID3 (
      .clock(clock),
      .reset(reset || mlast_w),

      .s_tvalid(svalid),
      .s_tready(sready_w),
      .s_tlast (slast),
      .s_tdata (sdata),

      .t_tvalid(tvalid),    // Allow the temp-register to be explicitly loaded
      .t_tready(tready_w),
      .t_tlast (tlast),
      .t_tdata (tdata),

      .m_tvalid(mvalid_w),
      .m_tready(mready_w),
      .m_tlast (mlast_w),
      .m_tdata (mdata_w)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_xsend;

  always @* begin
    case (xsend)
      TX_IDLE: dbg_xsend = "IDLE";
      TX_XPID: dbg_xsend = "XPID";
      TX_DATA: dbg_xsend = "DATA";
      TX_CRC0: dbg_xsend = "CRC0";
      TX_CRC1: dbg_xsend = "CRC1";
      TX_LAST: dbg_xsend = "LAST";
      TX_DONE: dbg_xsend = "DONE";
      TX_INIT: dbg_xsend = "INIT";
      TX_REGW: dbg_xsend = "REGW";
      TX_STOP: dbg_xsend = "STOP";
      default: dbg_xsend = "XXXX";
    endcase
  end

`endif


endmodule  // ulpi_encoder
