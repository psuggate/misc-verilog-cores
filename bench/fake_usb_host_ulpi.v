`timescale 1ns / 100ps
module fake_usb_host_ulpi (  /*AUTOARG*/
    // Outputs
    ulpi_clock_o,
    ulpi_dir_o,
    ulpi_nxt_o,
    usb_sof_o,
    crc_err_o,
    dev_enum_done_o,
    // Inouts
    ulpi_data_io,
    // Inputs
    clock,
    reset,
    ulpi_rst_ni,
    ulpi_stp_i,
    dev_enum_start_i
);

  input clock;
  input reset;

  output ulpi_clock_o;
  input ulpi_rst_ni;
  output ulpi_dir_o;
  output ulpi_nxt_o;
  input ulpi_stp_i;
  inout [7:0] ulpi_data_io;

  output usb_sof_o;
  output crc_err_o;

  // Control signals for testing
  input dev_enum_start_i;
  output dev_enum_done_o;


  // -- Constants & Settings -- //

  `include "usb_crc.vh"

  localparam HIGH_SPEED = 1;
  localparam TOKEN = 1;

  localparam TOK_OUT = 2'b00;
  localparam TOK_IN = 2'b10;
  localparam TOK_SETUP = 2'b11;


  // -- State & Signals -- //

  reg mvalid, sready, hsend, tstart, tvalid, tlast;
  wire svalid, mready, slast, hdone, tready;
  reg [1:0] htype, ttype;
  reg  [7:0] tdata;
  wire [7:0] sdata;

  reg hsend_q, ksend_q;
  reg [1:0] htype_q, ktype_q;
  reg [15:0] kdata_q;
  wire hdone_w, kdone_w;

  wire usb_rx_tvalid_w, usb_rx_tready_w, usb_rx_tlast_w;
  wire usb_tx_tvalid_w, usb_tx_tready_w, usb_tx_tlast_w;
  wire [7:0] usb_rx_tdata_w, usb_tx_tdata_w;

  wire tok_recv_w, rx_hrecv_w;
  wire [1:0] tok_type_w, rx_htype_w;
  wire [6:0] tok_addr_w;
  wire [3:0] tok_endp_w;


  // -- Input/Output Assignments -- //


  // -- Fake ULPI -- //

  localparam ST_INIT = 4'h0;
  localparam ST_RSTN = 4'h0;
  localparam ST_IDLE = 4'hf;

  reg [3:0] state;
  integer count;
  wire [31:0] cnext = count + 1;

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_INIT;
    end else begin
      case (state)
        ST_INIT: begin
          if (!ulpi_rst_ni) begin
            state   <= ST_RSTN;
            count   <= 0;

            hsend_q <= 1'b0;
            ksend_q <= 1'b0;

            sready  <= 1'b0;
            mvalid  <= 1'b0;
          end
        end

        ST_RSTN: begin
          if (ulpi_rst_ni) begin
            count <= cnext;
            if (cnext == 200) begin
              state <= ST_IDLE;
            end
          end
        end

        default: begin
        end
      endcase
    end
  end


  fake_ulpi_phy U_ULPI_PHY0 (
      .clock(clock),
      .reset(reset),

      .ulpi_clock_o(ulpi_clock_o),
      .ulpi_rst_ni (ulpi_rst_ni),
      .ulpi_dir_o  (ulpi_dir_o),
      .ulpi_nxt_o  (ulpi_nxt_o),
      .ulpi_stp_i  (ulpi_stp_i),
      .ulpi_data_io(ulpi_data_io),

      .usb_tvalid_i(usb_tx_tvalid_w),
      .usb_tready_o(usb_tx_tready_w),
      .usb_tlast_i (usb_tx_tlast_w),
      .usb_tdata_i (usb_tx_tdata_w),

      .usb_tvalid_o(usb_rx_tvalid_w),
      .usb_tready_i(usb_rx_tready_w),
      .usb_tlast_o (usb_rx_tlast_w),
      .usb_tdata_o (usb_rx_tdata_w)
  );


  // -- USB Packet Operations -- //

  wire [1:0] usb_rx_ttype_w;
  wire tdone;

  encode_packet #(
      .TOKEN(TOKEN)
  ) U_TX_USB_PACKET0 (
      .reset(reset),
      .clock(clock),

      .tx_tvalid_o(usb_tx_tvalid_w),
      .tx_tready_i(usb_tx_tready_w),
      .tx_tlast_o (usb_tx_tlast_w),
      .tx_tdata_o (usb_tx_tdata_w),

      .hsk_send_i(hsend_q),
      .hsk_done_o(hdone_w),
      .hsk_type_i(htype_q),

      .tok_send_i(ksend_q),
      .tok_done_o(kdone_w),
      .tok_type_i(ktype_q),
      .tok_data_i(kdata_q),

      .trn_tsend_i(tstart),
      .trn_ttype_i(ttype),
      .trn_tdone_o(tdone),

      .trn_tvalid_i(tvalid),
      .trn_tready_o(tready),
      .trn_tlast_i (tlast),
      .trn_tdata_i (tdata)
  );

  decode_packet U_RX_USB_PACKET0 (
      .reset(reset),
      .clock(clock),

      // USB packet-decoder status flags
      .usb_sof_o(usb_sof_o),
      .crc_err_o(crc_err_o),

      // ULPI -> decoder stream
      .ulpi_tvalid_i(svalid),
      .ulpi_tready_o(mready),
      .ulpi_tlast_i (slast),
      .ulpi_tdata_i (sdata),

      // Indicates that a (OUT/IN/SETUP) token was received
      .tok_recv_o(tok_recv_w),
      .tok_type_o(tok_type_w),
      .tok_addr_o(tok_addr_w),
      .tok_endp_o(tok_endp_w),

      // Data packet (OUT, DATA0/1/2 MDATA) received
      .out_tvalid_o(usb_rx_tvalid_w),
      .out_tready_i(usb_rx_tready_w),
      .out_tlast_o (usb_rx_tlast_w),
      .out_ttype_o (usb_rx_ttype_w),
      .out_tdata_o (usb_rx_tdata_w),

      // Handshake packet information
      .hsk_type_o(rx_htype_w),
      .hsk_recv_o(rx_hrecv_w)
  );


  //
  //  Simulation Tasks
  ///

  // -- Encode and Send a USB Data Packet -- //

  task send_packet;
    input [7:0] len;
    input [3:0] pid;
    input stub;
    begin
      integer count;

      sready  <= 1'b1;

      hsend_q <= 1'b0;
      htype_q <= 2'bx;

      tstart  <= 1'b1;
      ttype   <= pid[3:2];
      tvalid  <= 1'b1;
      tlast   <= 1'b0;
      tdata   <= $urandom;  // {~pid, pid};

      count   <= len;

      @(posedge clock);
      tstart <= 1'b0;

      while (sready) begin
        @(posedge clock);

        if (tready) begin
          tvalid <= count > 0;
          tlast  <= count == 1 && !stub;
          tdata  <= $urandom;

          count  <= count - 1;
        end

        if (svalid && slast) begin
          sready <= 1'b0;
        end
      end

      @(posedge clock);
      @(posedge clock);
    end
  endtask  // send_packet


  // -- Encode and Send a USB Token Packet -- //

  task send_token;
    input [6:0] adr;
    input [3:0] epn;
    input [1:0] typ;
    begin
      sready  <= 1'b1;

      ksend_q <= 1'b1;
      ktype_q <= typ;
      kdata_q <= {crc5({epn, adr}), epn, adr};

      @(posedge clock);

      while (ksend_q || !kdone_w) begin
        @(posedge clock);

        if (kdone_w) begin
          ksend_q <= 1'b0;
        end

        if (svalid && slast) begin
          sready <= 1'b0;
        end
      end

      @(posedge clock);
    end
  endtask  // send_token


  // -- Encode and Send an OUT Token, then 8B DATA0/1 Packet -- //

  task send_data;
    input [6:0] adr;
    input [3:0] epn;
    input odd;
    input [63:0] dat;
    begin
      integer count;

      send_token(adr, epn, TOK_OUT);

      sready <= 1'b1;
      count  <= 8;
      @(posedge clock);

      while (!tdone) begin
        @(posedge clock);
      end

      // todo: check for 'ACK'

      @(posedge clock);
    end
  endtask  // send_data


  // -- Encode and Send a USB Handshake Packet -- //

  task handshake;
    input [1:0] typ;
    begin
      sready  <= 1'b1;

      hsend_q <= 1'b1;
      htype_q <= typ;

      @(posedge clock);

      while (hsend_q || !hdone_w) begin
        @(posedge clock);

        if (hdone_w) begin
          hsend_q <= 1'b0;
        end

        if (svalid && slast) begin
          sready <= 1'b0;
        end
      end

      @(posedge clock);
    end
  endtask  // handshake


endmodule  // fake_usb_host_ulpi
