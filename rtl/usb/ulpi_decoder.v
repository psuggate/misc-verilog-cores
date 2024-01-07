`timescale 1ns / 100ps
module ulpi_decoder (
    input clock,
    input reset,

    // Raw ULPI IOB inputs
    input ibuf_dir,
    input ibuf_nxt,

    // Registered ULPI IOB inputs
    input ulpi_dir,
    input ulpi_nxt,
    input [7:0] ulpi_data,

    output crc_error_o,
    output crc_valid_o,
    output decode_idle_o,

    input [1:0] LineState,
    input [1:0] VbusState,
    input [1:0] RxEvent,

    output usb_sof_o,
    output tok_recv_o,
    output tok_ping_o,
    output [6:0] tok_addr_o,
    output [3:0] tok_endp_o,
    output hsk_recv_o,
    output usb_recv_o,

    output raw_tvalid_o,
    output raw_tlast_o,
    output [7:0] raw_tdata_o,

    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [3:0] m_tuser,
    output [7:0] m_tdata
);

  `include "usb_crc.vh"

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

  // Output datapath registers
  reg rx_tvalid, rx_tkeep, rx_tlast;
  reg [3:0] rx_tuser;
  reg [7:0] rx_tdata;

  // ULPI parser signals
  reg cyc_q, pid_q, dir_q;
  reg [7:0] dat_q;

  // USB packet-type parser signals
  reg hsk_q, tok_q, low_q, sof_q;
  wire pid_vld_w, istoken_w;
  wire [3:0] rx_pid_pw, rx_pid_nw;

  // CRC16 calculation & framing signals
  reg crc_error_flag, crc_valid_flag;
  reg  [15:0] crc16_q;
  wire [15:0] crc16_w;

  // USB token signals
  reg tok_recv_q, hsk_recv_q, usb_recv_q, sof_recv_q;
  reg  [10:0] token_data;
  wire [ 4:0] rx_crc5_w;


  // -- Output Assignments -- //

  // todo: good enough !?
  assign decode_idle_o = ~cyc_q;

  assign crc_error_o = crc_error_flag;
  assign crc_valid_o = crc_valid_flag;

  assign usb_sof_o = sof_recv_q;
  assign tok_recv_o = tok_recv_q;
  assign tok_addr_o = token_data[6:0];
  assign tok_endp_o = token_data[10:7];
  assign hsk_recv_o = hsk_recv_q;
  assign usb_recv_o = usb_recv_q;

  // Raw USB packets (including PID & CRC bytes)
  assign raw_tvalid_o = rx_tvalid;
  assign raw_tlast_o = rx_tlast;
  assign raw_tdata_o = rx_tdata;

  assign m_tvalid = rx_tvalid;
  assign m_tkeep = rx_tkeep;
  assign m_tlast = rx_tlast;
  assign m_tuser = rx_tuser;
  assign m_tdata = rx_tdata;


  // -- Capture Incoming USB Packets -- //

  // This signal goes high if 'RxActive' (or 'dir') de-asserts during packet Rx
  wire rx_end_w =
       ibuf_dir && ulpi_dir && !ulpi_nxt && ulpi_data[5:4] != RxActive ||
       !ibuf_dir && ulpi_dir;

  always @(posedge clock) begin
    dir_q <= ulpi_dir;

    if (reset) begin
      cyc_q <= 1'b0;
      pid_q <= 1'b0;
      dat_q <= 8'bx;

      rx_tvalid <= 1'b0;
      rx_tkeep <= 1'bx;
      rx_tlast <= 1'bx;
      rx_tuser <= 4'hx;
      rx_tdata <= 8'hx;
    end else begin
      if (cyc_q && rx_end_w) begin
        cyc_q <= 1'b0;
        pid_q <= 1'b0;
        dat_q <= 8'bx;

        rx_tvalid <= 1'b1;
        rx_tkeep <= 1'b0;
        rx_tlast <= 1'b1;
        rx_tuser <= rx_tuser;
        rx_tdata <= 8'bx;
      end else if (dir_q && ulpi_dir && ulpi_nxt) begin
        cyc_q <= 1'b1;
        pid_q <= cyc_q;
        dat_q <= ulpi_data;

        if (!cyc_q) begin
          rx_tvalid <= 1'b0;
          rx_tkeep  <= 1'bx;
          rx_tlast  <= 1'bx;
          rx_tuser  <= rx_tuser;
          rx_tdata  <= 8'hx;
        end else begin
          rx_tvalid <= 1'b1;
          rx_tkeep  <= pid_q;
          rx_tlast  <= 1'b0;
          rx_tuser  <= pid_q ? rx_tuser : dat_q[3:0];
          rx_tdata  <= dat_q;
        end
      end else begin
        rx_tvalid <= 1'b0;
        rx_tkeep  <= 1'b0;
        rx_tlast  <= 1'b0;
        rx_tuser  <= rx_tuser;
        rx_tdata  <= 8'bx;
      end
    end
  end


  // -- USB PID Parser -- //

  assign istoken_w = rx_pid_pw[1:0] == PID_TOKEN || rx_pid_pw == {SPC_PING, PID_SPECIAL};
  assign pid_vld_w = ulpi_dir && ulpi_nxt && dir_q && rx_pid_pw == rx_pid_nw;
  assign rx_pid_pw = ulpi_data[3:0];
  assign rx_pid_nw = ~ulpi_data[7:4];

  // Decode USB handshake packets
  always @(posedge clock) begin
    if (reset) begin
      hsk_q <= 1'b0;
    end else begin
      if (pid_vld_w && !cyc_q) begin
        hsk_q <= rx_pid_pw[1:0] == PID_HANDSHAKE;
      end else if (rx_end_w) begin
        hsk_q <= 1'b0;
      end
    end
  end

  // Note: these data are also used for the USB device address & endpoint
  always @(posedge clock) begin
    if (reset) begin
      tok_q <= 1'b0;
      sof_q <= 1'b0;
      low_q <= 1'b1;
    end else begin
      if (!tok_q && pid_vld_w && istoken_w) begin
        tok_q <= 1'b1;
        low_q <= 1'b1;
      end else if (tok_q && ulpi_nxt) begin
        token_data[7:0] <= low_q ? ulpi_data : token_data[7:0];
        token_data[10:8] <= low_q ? token_data[10:8] : ulpi_data[2:0];
        low_q <= ~low_q;
        tok_q <= ~rx_end_w;
      end else if (rx_end_w) begin
        tok_q <= 1'b0;
        low_q <= 1'b1;
      end else begin
        token_data <= token_data;
        low_q <= low_q;
      end
    end
  end

  always @(posedge clock) begin
    tok_recv_q <= tok_q && rx_end_w && rx_crc5_w == ulpi_data[7:3];
    sof_recv_q <= sof_q && rx_end_w && rx_crc5_w == ulpi_data[7:3];  // todo: ...
    hsk_recv_q <= hsk_q && rx_end_w;
    usb_recv_q <= cyc_q && rx_end_w && !tok_q && crc16_w == 16'h800d;  // todo: ...
  end


  // -- Early CRC16 calculation -- //

  assign rx_crc5_w = crc5({ulpi_data[2:0], token_data[7:0]});
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
      crc_error_flag <= 1'b0;
      crc_valid_flag <= 1'b0;
    end else if (tok_q && rx_end_w) begin
      crc_error_flag <= rx_crc5_w != ulpi_data[7:3];
      crc_valid_flag <= rx_crc5_w == ulpi_data[7:3];
    end else if (cyc_q && rx_end_w) begin
      crc_error_flag <= crc16_w != 16'h800d;
      crc_valid_flag <= crc16_w == 16'h800d;
    end else begin
      crc_valid_flag <= 1'b0;
    end
  end


endmodule  // ulpi_decoder
