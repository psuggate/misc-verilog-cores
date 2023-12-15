`timescale 1ns / 100ps
module ulpi_decoder
 (
  input clock,
  input reset,
  input ulpi_dir,
  input ulpi_nxt,
  input [7:0] ulpi_data,

  output crc_err_o,

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

  // USB 'RX_CMD[5:4]' bits
  localparam [1:0] RxActive = 2'b01;
  localparam [1:0] RxError  = 2'b10;

  // FSM RX states
  localparam [3:0] RX_IDLE = 4'h1;
  localparam [3:0] RX_XPID = 4'h2;
  localparam [3:0] RX_DATA = 4'h4;
  localparam [3:0] RX_LAST = 4'h8;


  // -- Signals & State -- //

  // State register
  reg [3:0] xrecv;

  // IOB registers
  reg dir_iob, nxt_iob;
  reg [7:0] dat_iob;

  // Output datapath registers
  reg rx_tvalid, rx_tlast;
  reg [7:0] rx_tdata;

  // ULPI parser signals
  reg cyc_q, dir_q;
  reg [7:0] dat_q;
  wire eop_w;

  // CRC16 calculation & framing signals
  reg crc_err_flag;
  reg [15:0] crc16_q;
  wire [15:0] crc16_w;


  // -- Output Assignments -- //

  assign crc_err_o = crc_err_flag;

  // Raw USB packets (including PID & CRC bytes)
  assign raw_tvalid_o = rx_tvalid;
  assign raw_tlast_o  = rx_tlast;
  assign raw_tdata_o  = rx_tdata;

  assign m_tkeep = xrecv == RX_DATA;
  assign m_tlast = xrecv == RX_LAST;


  // -- IOB Registers -- //

  always @(posedge clock) begin
    dir_iob <= ulpi_dir;
    nxt_iob <= ulpi_nxt; // note: can't be an IOB register (due to Tx. reqs)
    dat_iob <= ulpi_data;
  end


  // -- Capture Incoming USB Packets -- //

  always @(posedge clock) begin
    dir_q <= dir_iob;
  end

  // This signal goes high if 'RxActive' de-asserts during packet Rx

  wire end_w;

  assign eop_w = dir_iob && dat_iob[5:4] != RxActive || !dir_iob;
  assign end_w = dir_q && (cyc_q && !nxt_iob && dir_iob && dat_iob[5:4] != RxActive || !dir_iob);

  always @(posedge clock) begin
    if (reset) begin
      cyc_q <= 1'b0;
      dat_q <= 8'bx;

      rx_tvalid <= 1'b0;
      rx_tlast <= 1'bx;
      rx_tdata <= 8'bx;
    end else begin
      if (dir_q && dir_iob && nxt_iob) begin
        cyc_q <= 1'b1;
        dat_q <= dat_iob;

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


  // -- Early CRC16 calculation -- //

  assign crc16_w = crc16(dat_iob, crc16_q);

  always @(posedge clock) begin
    if (!cyc_q) begin
      crc16_q <= 16'hffff;
    end else if (cyc_q && nxt_iob) begin
      crc16_q <= crc16_w;
    end else begin
      crc16_q <= crc16_q;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      crc_err_flag <= 1'b0;
    end else if (xrecv == RX_DATA && end_w) begin
      crc_err_flag <= crc16_q != 16'h800d;
    end
  end


  // -- ULPI Packet Parser FSM -- //

  always @(posedge clock) begin
    if (xrecv == RX_IDLE && rx_tvalid) begin
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      m_tvalid <= 1'b0;
      m_tuser  <= 4'bx;
      m_tdata  <= 8'bx;
      xrecv    <= RX_IDLE;
    end else begin
      case (xrecv)
        default: begin // RX_IDLE
          m_tvalid <= 1'b0;
          m_tuser  <= rx_tvalid ? rx_tdata[3:0] : 4'bx;
          m_tdata  <= 8'bx;
          xrecv    <= rx_tvalid ? RX_XPID : RX_IDLE;
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
          xrecv    <= !rx_tvalid || rx_tvalid && rx_tlast ? RX_IDLE : xrecv;
        end
      endcase
    end
  end


endmodule // ulpi_decoder
