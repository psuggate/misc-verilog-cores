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

    input [1:0] LineState,
    input [1:0] VbusState,
    input [1:0] RxEvent,

    output [6:0] tok_addr_o,
    output [3:0] tok_endp_o,

    output raw_tvalid_o,
    output raw_tlast_o,
    output [7:0] raw_tdata_o,

    output reg m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output reg [3:0] m_tuser,
    output reg [7:0] m_tdata
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

  // FSM RX states
  localparam [4:0] RX_IDLE = 5'h01;
  localparam [4:0] RX_XPID = 5'h02;
  localparam [4:0] RX_DATA = 5'h04;
  localparam [4:0] RX_LAST = 5'h08;
  localparam [4:0] RX_DONE = 5'h10;


  // -- Signals & State -- //

  // State register
  reg [4:0] xrecv;

  // Output datapath registers
  reg rx_tvalid, rx_tlast;
  reg [7:0] rx_tdata;

  // ULPI parser signals
  reg cyc_q, dir_q;
  reg [7:0] dat_q;
  wire eop_w, end_w;

  // USB packet-type parser signals
  reg hsk_q, tok_q, low_q;
  wire pid_vld_w, istoken_w;
  wire [3:0] rx_pid_pw, rx_pid_nw;

  // CRC16 calculation & framing signals
  reg crc_error_flag, crc_valid_flag;
  reg  [15:0] crc16_q;
  wire [15:0] crc16_w;

  // USB token signals
  reg  [10:0] token_data;
  reg  [ 4:0] token_crc5;
  wire [ 4:0] rx_crc5_w;


  // -- Output Assignments -- //

  assign crc_error_o = crc_error_flag;
  assign crc_valid_o = crc_valid_flag;

  assign tok_addr_o = token_data[6:0];
  assign tok_endp_o = token_data[10:7];

  // Raw USB packets (including PID & CRC bytes)
  assign raw_tvalid_o = rx_tvalid;
  assign raw_tlast_o = rx_tlast;
  assign raw_tdata_o = rx_tdata;

  assign m_tkeep = xrecv == RX_DATA;
  assign m_tlast = xrecv == RX_LAST;


  // -- Capture Incoming USB Packets -- //

  wire rx_cmd_w = ulpi_dir && ibuf_dir && !ibuf_nxt;

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
  end

  // This signal goes high if 'RxActive' de-asserts during packet Rx
  assign eop_w = ulpi_dir && ulpi_data[5:4] != RxActive || !ulpi_dir;
  assign end_w = dir_q && (cyc_q && !ulpi_nxt && ulpi_dir && ulpi_data[5:4] != RxActive || !ulpi_dir);

  always @(posedge clock) begin
    if (reset) begin
      cyc_q <= 1'b0;
      dat_q <= 8'bx;

      rx_tvalid <= 1'b0;
      rx_tlast <= 1'bx;
      rx_tdata <= 8'bx;
    end else begin
      if (dir_q && ulpi_dir && ulpi_nxt) begin
        cyc_q <= 1'b1;
        dat_q <= ulpi_data;

        if (!cyc_q) begin
          rx_tvalid <= 1'b0;
          rx_tlast  <= 1'bx;
          rx_tdata  <= 8'bx;
        end else begin
          rx_tvalid <= 1'b1;
          rx_tlast  <= 1'b0;
          rx_tdata  <= dat_q;
        end
      end else if (cyc_q && dir_q && eop_w) begin
        cyc_q <= 1'b0;
        dat_q <= 8'bx;

        rx_tvalid <= 1'b1;
        rx_tlast <= 1'b1;
        rx_tdata <= dat_q;
      end else begin
        rx_tvalid <= 1'b0;
        rx_tlast  <= 1'b0;
        rx_tdata  <= 8'bx;
      end
    end
  end


  // -- USB PID Parser -- //

  assign istoken_w = rx_pid_pw[1:0] == PID_TOKEN || rx_pid_pw == {SPC_PING, PID_SPECIAL};
  assign pid_vld_w = ulpi_dir && ulpi_nxt && dir_q && rx_pid_pw == rx_pid_nw;
  assign rx_pid_pw = ulpi_data[3:0];
  assign rx_pid_nw = ~ulpi_data[7:4];

  always @(posedge clock) begin
    if (reset) begin
      hsk_q <= 1'b0;
    end else begin
      if (pid_vld_w && !cyc_q) begin
        hsk_q <= rx_pid_pw[1:0] == PID_HANDSHAKE;
      end else if (xrecv == RX_DONE) begin
        hsk_q <= 1'b0;
      end
    end
  end


  // -- Early CRC16 calculation -- //

  assign rx_crc5_w = crc5(token_data);
  assign crc16_w   = crc16(ulpi_data, crc16_q);

  // Note: these data are also used for the USB device address & endpoint
  always @(posedge clock) begin
    if (!cyc_q && pid_vld_w && istoken_w) begin
      tok_q <= 1'b1;
      low_q <= 1'b1;
    end else if (end_w) begin
      tok_q <= 1'b0;
      low_q <= 1'bx;
    end else if (tok_q && ulpi_nxt) begin
      token_data[7:0] <= low_q ? ulpi_data : token_data[7:0];
      token_data[10:8] <= low_q ? token_data[10:8] : ulpi_data[2:0];
      token_crc5 <= low_q ? token_crc5 : ulpi_data[7:3];
      low_q <= ~low_q;
    end else begin
      token_data <= token_data;
      token_crc5 <= token_crc5;
      low_q <= low_q;
    end
  end

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
    end else if (xrecv == RX_XPID && tok_q && end_w) begin
      crc_error_flag <= rx_crc5_w != token_crc5;
      crc_valid_flag <= rx_crc5_w == token_crc5;
    end else if ((xrecv == RX_XPID || xrecv == RX_DATA) && end_w) begin
      crc_error_flag <= crc16_q != 16'h800d;
      crc_valid_flag <= crc16_q == 16'h800d;
    end else begin
      crc_valid_flag <= 1'b0;
    end
  end


  // -- ULPI Packet Parser FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      m_tvalid <= 1'b0;
      m_tuser  <= 4'bx;
      m_tdata  <= 8'bx;
      xrecv    <= RX_IDLE;
    end else begin
      case (xrecv)
        default: begin  // RX_IDLE
          m_tvalid <= rx_tvalid & hsk_q ? 1'b1 : 1'b0;
          m_tuser  <= rx_tvalid ? rx_tdata[3:0] : 4'bx;
          m_tdata  <= 8'bx;
          xrecv    <= rx_tvalid ? (hsk_q ? RX_LAST : RX_XPID) : RX_IDLE;
        end

        RX_XPID: begin
          m_tvalid <= rx_tvalid;
          m_tuser  <= m_tuser;
          m_tdata  <= rx_tdata;
          xrecv    <= end_w ? RX_LAST : rx_tvalid ? RX_DATA : xrecv;
        end

        RX_DATA: begin
          m_tvalid <= rx_tvalid;
          m_tuser  <= m_tuser;
          m_tdata  <= end_w ? 8'bx : rx_tdata;
          xrecv    <= end_w ? RX_LAST : xrecv;
        end

        RX_LAST: begin
          m_tvalid <= 1'b0;
          m_tuser  <= 4'bx;
          m_tdata  <= 8'bx;
          xrecv    <= RX_DONE;
        end

        RX_DONE: begin
          m_tvalid <= 1'b0;
          m_tuser  <= 4'bx;
          m_tdata  <= 8'bx;
          // xrecv    <= rx_tvalid ? xrecv : RX_IDLE;
          xrecv    <= RX_IDLE;
        end
      endcase
    end
  end


endmodule  // ulpi_decoder
