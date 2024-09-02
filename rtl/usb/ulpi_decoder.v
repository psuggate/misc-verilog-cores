`timescale 1ns / 100ps
/**
 * Decode USB packets from the ULPI input signals.
 * 
 * Control signals:
 *  + crc_valid_o --  strobes HI after a successful CRC;
 *  + crc_error_o --  asserts HI after a CRC failure, and deasserts when another
 *                    packet is received;
 *  + tok_recv_o  --  strobes HI after a token has been received, and CRC pass;
 *  + tok_addr_o  --  address value of a successfully-decoded token packet;
 *  + tok_endp_o  --  end-point number of a successfully-decoded token packet;
 *  + tok_ping_o  --  indicates an end-point is being pinged, for space to store
 *                    an OUT packet;
 *  + usb_recv_o  --  strobes HI after successfully receiving an entire DATAx
 *                    packet;
 *  + hsk_recv_o  --  strobes HI after a handshake packet has been received;
 *  + sof_recv_o  --  strobes HI after decoding a Start-Of-Frame packet;
 *  + dec_idle_o  --  asserts HI when not processing a USB packet;
 *  + eop_recv_o  --  strobes HI when USB line-state indicates End-Of-Packet;
 *
 * Todo:
 *  - on PID-error, need to drop all bytes until line-state returns to idle !?
 *  - only assert 'tlast' when packet-length is not the maximum, so that packets
 *    can be combined into larger transfers -- and ZDP's are required to mark
 *    the end of a transfer when the total-length is a multiple of the maximum
 *    packet length !?
 */
module ulpi_decoder #(
    parameter DEBUG = 0,
    parameter USE_MAX_LENGTHS = 1,  // Todo
    parameter MAX_BULK_LENGTH = 512,
    parameter MAX_CTRL_LENGTH = 64
) (
    input clock,
    input reset,

    input [1:0] LineState,

    input ulpi_dir,
    input ulpi_nxt,
    input [7:0] ulpi_data,

    output crc_error_o,
    output crc_valid_o,
    output [10:0] sof_count_o,
    output sof_recv_o,
    output eop_recv_o,
    output dec_idle_o,
    output dec_actv_o,

    output tok_recv_o,
    output tok_ping_o,
    output [6:0] tok_addr_o,
    output [3:0] tok_endp_o,
    output hsk_recv_o,
    output usb_recv_o,

    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [3:0] m_tuser,  // USB PID
    output [7:0] m_tdata
);

  `include "usb_defs.vh"

  // -- Constants -- //

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] SPC_PING = 2'b01;

  localparam [1:0] PID_SPECIAL = 2'b00;
  localparam [1:0] PID_TOKEN = 2'b01;
  localparam [1:0] PID_HANDSHAKE = 2'b10;
  localparam [1:0] PID_DATA = 2'b11;

  // USB 'RX_CMD[5:4]' bits
  localparam [1:0] RxActive = 2'b01;
  localparam [1:0] RxError = 2'b11;


  // -- Signals & State -- //

  // USB packet-receive signals
  reg tok_recv_q, tok_ping_q, hsk_recv_q, usb_recv_q, sof_recv_q, dec_actv_q;
  reg tvalid, tlast, tkeep;
  reg [10:0] cnt_q;
  reg [ 3:0] tuser;
  reg [ 7:0] tdata;

  // End-of-Packet state registers
  reg eop_q, rcv_q;

  // CRC16 calculation & framing signals
  reg crc_error_flag, crc_valid_flag;
  reg  [15:0] crc16_q;
  wire [15:0] crc16_w;
  reg  [10:0] token_data;
  wire [ 4:0] rx_crc5_w;


  assign crc_error_o = crc_error_flag;
  assign crc_valid_o = crc_valid_flag;
  assign sof_count_o = cnt_q;
  assign sof_recv_o = sof_recv_q;
  assign eop_recv_o = eop_q;
  assign dec_idle_o = ~cyc_q;
  assign dec_actv_o = dec_actv_q;

  assign tok_recv_o = tok_recv_q;
  assign tok_ping_o = tok_ping_q;
  assign tok_addr_o = addr_q;
  assign tok_endp_o = endp_q;
  assign hsk_recv_o = hsk_recv_q;
  assign usb_recv_o = usb_recv_q;

  assign m_tvalid = tvalid;
  assign m_tlast = tlast;
  assign m_tkeep = tkeep;
  assign m_tuser = tuser;
  assign m_tdata = tdata;


  // -- Pipeline Control -- //

  reg dir_q, cyc_q, tok_q, hsk_q;
  wire rx_end_w, pid_err_w, pid_vld_w, istoken_w;
  wire [3:0] rx_pid_w;

  assign rx_end_w  = !ulpi_dir || ulpi_dir && !ulpi_nxt && ulpi_data[5:4] != RxActive;
  assign rx_pid_w  = ulpi_data[3:0];

  // Todo:
  assign pid_err_w = ulpi_dir && ulpi_nxt && dir_q && rx_pid_w != ~ulpi_data[7:4];

  assign pid_vld_w = ulpi_dir && ulpi_nxt && dir_q && rx_pid_w == ~ulpi_data[7:4];
  assign istoken_w = rx_pid_w[1:0] == PID_TOKEN || rx_pid_w == {SPC_PING, PID_SPECIAL};

  // Frames a USB packet-receive transfer cycle //
  always @(posedge clock) begin
    dir_q <= ulpi_dir;

    if (reset || rx_end_w) begin
      cyc_q <= 1'b0;
      tok_q <= 1'b0;
      hsk_q <= 1'b0;
    end else if (pid_vld_w) begin
      cyc_q <= 1'b1;

      if (!cyc_q) begin
        hsk_q <= rx_pid_w[1:0] == PID_HANDSHAKE;
        tok_q <= istoken_w;
      end
    end

  end

  // USB PID is output as a 4-bit AXI4-Stream 'tuser' value //
  // Note: only updates whenever a new USB packet is received.
  always @(posedge clock) begin
    if (reset) begin
      tuser <= `USBPID_NAK;
    end else if (!cyc_q && pid_vld_w) begin
      tuser <= rx_pid_w;
    end

    dec_actv_q <= ~cyc_q & pid_vld_w;
  end


  // -- End-of-Packet -- //

  wire eop_w = (cyc_q || dir_q && ulpi_dir) && !ulpi_nxt &&
       (ulpi_data[5:4] != RxActive || ulpi_data[3:2] == 2'b00);

  always @(posedge clock) begin
    if (reset) begin
      eop_q <= 1'b0;
      rcv_q <= 1'b0;
    end else begin
      if (rcv_q && (LineState == 2'd0 || eop_w)) begin
        eop_q <= 1'b1;
        rcv_q <= 1'b0;
      end else if (cyc_q && !hsk_q && !tok_q) begin
        eop_q <= 1'b0;
        rcv_q <= 1'b1;
      end else begin
        eop_q <= 1'b0;
        rcv_q <= rcv_q;
      end
    end
  end


  // -- USB Token Handling -- //

  reg sof_q, low_q;
  reg  [ 3:0] endp_q;
  reg  [ 6:0] addr_q;
  wire [10:0] token_w;

  assign token_w = {dat_q[2:0], out_q};

  // Strobes for when we receive a TOKEN or SOF //
  always @(posedge clock) begin
    if (cyc_q && rx_end_w && rx_crc5_w == dat_q[7:3]) begin
      tok_recv_q <= tok_q && !sof_q;
      tok_ping_q <= tuser == {SPC_PING, PID_SPECIAL};
      sof_recv_q <= sof_q;
    end else begin
      tok_recv_q <= 1'b0;
      tok_ping_q <= 1'b0;
      sof_recv_q <= 1'b0;
    end
    hsk_recv_q <= hsk_q && rx_end_w;
    usb_recv_q <= cyc_q && !tok_q && rx_end_w && crc16_q == 16'h800d;  // todo: ...
  end

  // Note: these data are also used for the USB device address & endpoint
  always @(posedge clock) begin
    if (reset) begin
      sof_q  <= 1'b0;
      low_q  <= 1'b1;
      endp_q <= 0;
      addr_q <= 0;
    end else begin
      // Decode USB Start-of-Frame (SOF) Packets
      if (!tok_q && pid_vld_w && rx_pid_w[3:2] == TOK_SOF) begin
        sof_q <= 1'b1;
      end else if (rx_end_w) begin
        sof_q <= 1'b0;
      end

      if (!tok_q && pid_vld_w && istoken_w) begin
        low_q <= 1'b1;
      end else if (tok_q && ulpi_nxt) begin
        if (low_q && !sof_q) begin
          {endp_q[0], addr_q} <= ulpi_data;
        end else if (!sof_q) begin
          endp_q[3:1] <= ulpi_data[2:0];
        end
        low_q <= ~low_q;
      end
    end
  end


  // -- Early CRC16 calculation -- //

  assign rx_crc5_w = crc5(token_w);
  assign crc16_w   = crc16(ulpi_data, crc16_q);

  always @(posedge clock) begin
    if (!cyc_q) begin
      crc16_q <= 16'hffff;
    end else if (cyc_q && ulpi_nxt) begin
      crc16_q <= crc16_w;
    end else begin
      crc16_q <= crc16_q;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      if (DEBUG) begin
        cnt_q <= 11'd0;
      end
      crc_error_flag <= 1'b0;
      crc_valid_flag <= 1'b0;
    end else if (rx_end_w && cyc_q) begin
      if (!hsk_q && !tok_q) begin
        crc_error_flag <= crc16_q != 16'h800d;
        crc_valid_flag <= crc16_q == 16'h800d;
      end else if (sof_q) begin
        crc_error_flag <= rx_crc5_w != dat_q[7:3];
        crc_valid_flag <= rx_crc5_w == dat_q[7:3];
        cnt_q <= token_w;
      end else if (tok_q) begin
        crc_error_flag <= rx_crc5_w != dat_q[7:3];
        crc_valid_flag <= rx_crc5_w == dat_q[7:3];
      end
    end else begin
      crc_valid_flag <= 1'b0;
    end
  end


  //
  // Stage I: Capture registers
  // Note: When receiving USB packets, capture data whenever 'nxt' is asserted,
  // and drop the data when the transfer ends.
  reg stb_q;
  reg [7:0] dat_q;

  always @(posedge clock) begin
    if (reset) begin
      stb_q <= 1'b0;
      dat_q <= 8'bx;
    end else begin
      if (dir_q && ulpi_dir && ulpi_nxt) begin
        stb_q <= cyc_q;
        dat_q <= ulpi_data;
      end else begin
        stb_q <= stb_q && cyc_q && !rx_end_w;
      end
    end
  end

  //
  // Stage II: Pipeline registers
  // Note: Fills up the registers as 'nxt' clocks additional data in, and drops
  // stored data when a transaction ends.
  reg vld_q;
  reg [7:0] out_q;

  always @(posedge clock) begin
    if (reset || rx_end_w) begin
      vld_q <= 1'b0;
      out_q <= 8'bx;
    end else if (ulpi_nxt) begin
      vld_q <= stb_q;
      out_q <= dat_q;
    end
  end

  //
  // Stage III: Output registers
  // Note: Only transfers-out data when there are two bytes stored in the input
  // registers/pipeline.
  always @(posedge clock) begin
    if (reset) begin
      tvalid <= 1'b0;
      tlast  <= 1'b0;
      tkeep  <= 1'b0;
      tdata  <= 8'bx;
    end else begin
      tvalid <= cyc_q;
      tlast  <= cyc_q && rx_end_w;
      if (ulpi_nxt && stb_q && vld_q) begin
        tkeep <= 1'b1;
        tdata <= out_q;
      end else begin
        tkeep <= 1'b0;
        tdata <= 8'bx;
      end
    end
  end


  //
  // If supporting multipe-packet single-transfers.
  // Todo:
  //  - if USB packet-length > MAX_LENGTH, then issue a 'stp' ?!
  //  - flag for "max_length_packet" !?
  //  - but then would need to handle control-pipe lengths, of 64 bytes ??
  //
  localparam CBITS = $clog2(MAX_BULK_LENGTH);
  localparam CSB = CBITS - 1;

  reg  [  CSB:0] len_q;
  wire [CBITS:0] len_w;

  assign len_w = len_q + 1;

  always @(posedge clock) begin
    if (reset || rx_end_w) begin
      len_q <= 0;
    end else begin

      if (tvalid && tkeep) begin
        len_q <= len_w[CSB:0];
      end

    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  reg [47:0] dbg_pid;

  always @* begin
    case (tuser)
      `USBPID_OUT:   dbg_pid = "OUT";
      `USBPID_IN:    dbg_pid = "IN";
      `USBPID_SOF:   dbg_pid = "SOF";
      `USBPID_SETUP: dbg_pid = "SETUP";
      `USBPID_DATA0: dbg_pid = "DATA0";
      `USBPID_DATA1: dbg_pid = "DATA1";
      `USBPID_DATA2: dbg_pid = "DATA2";
      `USBPID_MDATA: dbg_pid = "MDATA";
      `USBPID_ACK:   dbg_pid = "ACK";
      `USBPID_NAK:   dbg_pid = "NAK";
      `USBPID_STALL: dbg_pid = "STALL";
      `USBPID_NYET:  dbg_pid = "NYET";
      `USBPID_PRE:   dbg_pid = "PRE";
      `USBPID_ERR:   dbg_pid = "ERR";
      `USBPID_SPLIT: dbg_pid = "SPLIT";
      `USBPID_PING:  dbg_pid = "PING";
      default:       dbg_pid = " ??? ";
    endcase
  end

`endif  /* __icarus */


endmodule  /* ulpi_decoder */
