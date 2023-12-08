`timescale 1ns / 100ps
//
// Based on project 'https://github.com/ObKo/USBCore'
// License: MIT
//  Copyright (c) 2021 Dmitry Matyunin
//  Copyright (c) 2023 Patrick Suggate
//
module decode_packet (
    input reset,
    input clock,

    output usb_sof_o,
    output crc_err_o,

    input ulpi_tvalid_i,
    output ulpi_tready_o,
    input ulpi_tlast_i,
    input [7:0] ulpi_tdata_i,

    output tok_recv_o,
    output tok_ping_o,
    output [1:0] tok_type_o,
    output [6:0] tok_addr_o,
    output [3:0] tok_endp_o,

    // Data packet (OUT, DATA0/1/2 MDATA) received
    output out_recv_o,
    output [1:0] out_type_o,  // OUT DATA0/1/2 MDATA

    output out_tvalid_o,
    input out_tready_i,  // todo
    output out_tlast_o,
    output [7:0] out_tdata_o,

    output hsk_recv_o,
    output [1:0] hsk_type_o  // 00 - ACK, 10 - NAK, 11 - STALL, 01 - NYET
);

  `include "usb_crc.vh"

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam  [6:0]
	ST_IDLE      = 7'h01,
	ST_SOF       = 7'h02,
	ST_SOF_CRC   = 7'h04,
	ST_TOKEN     = 7'h08,
	ST_TOKEN_CRC = 7'h10,
	ST_DATA      = 7'h20,
	ST_DATA_CRC  = 7'h40;

  reg [ 6:0] state;

  reg [10:0] token_data;
  reg [ 4:0] token_crc5;
  reg [7:0] rx_buf1, rx_buf0;
  wire [15:0] crc16_w;
  wire [ 4:0] rx_crc5_w;
  wire [3:0] rx_pid_pw, rx_pid_nw;
  reg [15:0] crc16_q;

  reg sof_flag_q, crc_err_flag;
  reg tok_recv_q, hsk_recv_q, out_recv_q;
  reg [1:0] trn_type_q;

  reg rx_vld0, rx_vld1, tvalid_q;
  wire third_w;


  // -- Input/Output Assignments -- //

  assign usb_sof_o = sof_flag_q;
  assign crc_err_o = crc_err_flag;

  // todo: theoretically, this can fail !?
  // todo: implement the PING protocol !?
  // todo: what does the ULPI PHY do when STP is asserted mid-packet !?
  assign ulpi_tready_o = 1'b1;

  assign hsk_recv_o = hsk_recv_q;
  assign hsk_type_o = trn_type_q;

  assign tok_recv_o = tok_recv_q;
  assign tok_type_o = trn_type_q;  // OUT/IN/SETUP
  assign tok_addr_o = token_data[6:0];
  assign tok_endp_o = token_data[10:7];

  // Rx data-path (from USB host) to either USB config OR bulk EP cores
  assign out_recv_o = out_recv_q;
  assign out_type_o = trn_type_q;  // DATA0/1/2 MDATA

  assign out_tvalid_o = tvalid_q;
  assign out_tlast_o = ulpi_tlast_i;
  assign out_tdata_o = rx_buf1;


  // -- Internal Signals -- //

  assign rx_pid_pw = ulpi_tdata_i[3:0];
  assign rx_pid_nw = ~ulpi_tdata_i[7:4];
  assign rx_crc5_w = crc5(token_data);


  // -- Rx Data -- //

  // Asserted from the 3rd byte onwards (so after PID and DATA[0])
  // Note: if asserted, then 'ulpi_tdata_i' is at least the 3rd byte
  assign third_w = rx_vld0 && !rx_vld1;

  always @(posedge clock) begin
    if (state == ST_IDLE) begin
      {rx_vld1, rx_vld0} <= 2'b00;
    end else if (ulpi_tvalid_i) begin
      {rx_vld1, rx_vld0} <= {rx_vld0, 1'b1};
    end

    if (ulpi_tvalid_i && ulpi_tready_o) begin
      {rx_buf1, rx_buf0} <= {rx_buf0, ulpi_tdata_i};
    end else begin
      {rx_buf1, rx_buf0} <= {rx_buf1, rx_buf0};
    end
  end

  always @(posedge clock) begin
    if (state == ST_DATA) begin
      tvalid_q <= ulpi_tvalid_i && !ulpi_tlast_i && rx_vld0;
    end else begin
      tvalid_q <= 1'b0;
    end
  end


  // -- Rx Data CRC Calculation -- //

  reg vld_q;

  assign crc16_w = crc16(rx_buf0, crc16_q);

  always @(posedge clock) begin
    vld_q <= ulpi_tvalid_i && ulpi_tready_o;

    if (!rx_vld0) begin
      crc16_q <= 16'hffff;
    end else if (!vld_q) begin
      crc16_q <= crc16_q;
    end else begin
      crc16_q <= crc16_w;
    end
  end


  // -- CRC-Error, Start-Of-Frame, and Token-Received Signals -- //

  // Strobes that indicate the start and end of a (received) packet.
  // todo: unify the SOF and TOKEN states !?
  always @(posedge clock) begin
    tok_recv_q <= state[4] && token_crc5 == rx_crc5_w;
    sof_flag_q <= state[2] && token_crc5 == rx_crc5_w;
  end

  reg tok_ping_q;

  assign tok_ping_o = tok_ping_q;

  always @(posedge clock) begin
    if (reset) begin
      tok_ping_q <= 1'b0;
    end else if (state == ST_IDLE) begin
      if (ulpi_tvalid_i && rx_pid_pw == rx_pid_nw && rx_pid_pw[3:0] == 4'b0100) begin
        tok_ping_q <= 1'b1;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      crc_err_flag <= 1'b0;
    end else if (state == ST_SOF_CRC || state == ST_TOKEN_CRC) begin
      crc_err_flag <= token_crc5 != rx_crc5_w;
    end else if (state == ST_DATA_CRC) begin
      crc_err_flag <= crc16_w != 16'h800d;
    end
  end


  // -- USB Address and Endpoint Registers -- //

  // Note: these data are also used for the USB device address & endpoint
  always @(posedge clock) begin
    case (state)
      ST_TOKEN, ST_SOF: begin
        if (ulpi_tvalid_i) begin
          token_data[7:0] <= rx_vld0 ? token_data[7:0] : ulpi_tdata_i;
          token_data[10:8] <= third_w ? ulpi_tdata_i[2:0] : token_data[10:8];
          token_crc5 <= third_w ? ulpi_tdata_i[7:3] : token_crc5;
        end
      end
      default: begin
        token_data <= token_data;
        token_crc5 <= token_crc5;
      end
    endcase
  end


  // -- Rx FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE: begin
          if (ulpi_tvalid_i && rx_pid_pw == rx_pid_nw) begin
            if (rx_pid_pw == 4'b0101) begin
              state <= ST_SOF;
            end else if (rx_pid_pw[1:0] == 2'b01 || rx_pid_pw[3:0] == 4'b0100) begin
              state <= ST_TOKEN;
            end else if (rx_pid_pw[1:0] == 2'b11) begin
              state <= ST_DATA;
            end
          end
        end

        ST_SOF: begin
          if (ulpi_tvalid_i && ulpi_tlast_i) begin
            state <= ST_SOF_CRC;
          end
        end

        ST_TOKEN: begin
          if (ulpi_tvalid_i && ulpi_tlast_i) begin
            state <= ST_TOKEN_CRC;
          end
        end

        ST_DATA: begin
          if (ulpi_tvalid_i && ulpi_tlast_i) begin
            state <= ST_DATA_CRC;
          end
        end

        ST_SOF_CRC: state <= ST_IDLE;
        ST_TOKEN_CRC: state <= ST_IDLE;
        ST_DATA_CRC: state <= ST_IDLE;
        default: state <= ST_IDLE;
      endcase
    end
  end


  // -- Transaction Type Register -- //

  always @(posedge clock) begin
    if (ulpi_tvalid_i && state == ST_IDLE && rx_pid_pw == rx_pid_nw) begin
      trn_type_q <= rx_pid_pw[3:2];
      out_recv_q <= rx_pid_pw[1:0] == 2'b11;
      hsk_recv_q <= rx_pid_pw[1:0] == 2'b10;
    end else begin
      out_recv_q <= 1'b0;
      hsk_recv_q <= 1'b0;
    end
  end


endmodule  // decode_packet
