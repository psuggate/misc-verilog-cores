`timescale 1ns / 100ps
module transaction_tb;

  `include "usb_crc.vh"

  localparam TOK_OUT = 2'b00;
  localparam TOK_IN = 2'b10;
  localparam TOK_SETUP = 2'b11;


  // -- Simulation Data -- //

  initial begin
    $dumpfile("transaction_tb.vcd");
    $dumpvars;

    #8000 $finish;  // todo ...
  end


  // -- Globals -- //

  reg osc = 1'b1;
  reg rst = 1'b0;
  wire clock, reset;

  assign clock = osc;
  assign reset = rst;

  always #5.0 osc <= ~osc;

  initial begin
    rst <= 1'b1;
    #20 rst <= 1'b0;
  end


  // -- Simulation Signals -- //

  reg sready, hsend, tstart, tvalid, tlast;
  wire svalid, slast, hdone, tready;
  reg [1:0] htype, ttype;
  reg [7:0] tdata;
  wire [7:0] sdata;

  reg ksend;
  reg [1:0] ktype;
  wire kdone;
  reg [15:0] kdata;


  // -- Initialisation -- //

  initial begin : Stimulus
    @(posedge clock);

    while (reset) begin
      @(posedge clock);

      sready <= 1'b0;
      tstart <= 1'b0;
      tvalid <= 1'b0;
      tlast  <= 1'b0;

      hsend  <= 1'b0;
      ksend  <= 1'b0;
    end

    @(posedge clock);
    @(posedge clock);
    send_token(0, 1, 2'b00);  // Set EP=1 OUT address

    @(posedge clock);
    @(posedge clock);
    send_token(0, 1, 2'b10);  // Set EP=1 IN address

    @(posedge clock);
    @(posedge clock);
    send_packet(8'd5, 4'b0011, 1);

    @(posedge clock);
    @(posedge clock);
    handshake(2'b00);

    @(posedge clock);
    @(posedge clock);
    send_packet(8'd5, 4'b0011, 0);

    #40 @(posedge clock);
    $finish;
  end


  // -- Stimulus State and Signals -- //

  wire usb_configured_w;
  wire [6:0] usb_addr_w;
  wire [7:0] usb_conf_w;

  wire ctl0_select_w, ctl0_accept_w, ctl0_error_w;

  // From/to USB decoder/encoder
  wire usb_rx_tvalid_w, usb_rx_tready_w, usb_rx_tlast_w;
  wire usb_tx_tvalid_w, usb_tx_tready_w, usb_tx_tlast_w;
  wire [7:0] usb_rx_tdata_w, usb_tx_tdata_w;

  wire ctl_rx_start_w;
  wire [7:0] ctl_rx_rtype_w, ctl_rx_rargs_w;
  wire [15:0] ctl_rx_value_w, ctl_rx_index_w, ctl_rx_length_w;

  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w;
  wire cfgi_tvalid_w, cfgi_tready_w, cfgi_tlast_w;
  wire [7:0] ctl0_tdata_w, cfgi_tdata_w;

  wire blko_tvalid_w, blko_tready_w, blko_tlast_w;
  wire blki_tvalid_w, blki_tready_w, blki_tlast_w;
  wire [7:0] blko_tdata_w, blki_tdata_w;

  wire tx_hsend_w, tx_hsent_w, usb_rx_trecv_w, usb_tx_tsend_w, usb_tx_tsent_w;
  wire [1:0] usb_rx_ttype_w, usb_tx_ttype_w, tx_htype_w;


  // -- Test-Module Output Checker -- //

  wire tok_recv_w, rx_hrecv_w, mvalid, mready, mend;
  wire [1:0] tok_type_w, mtype, rx_htype_w;
  wire usb_sof, crc_err, hrecv, tdone;
  wire [6:0] tok_addr_w;
  wire [3:0] tok_endp_w;
  wire [7:0] mdata;
  reg xready = 1'b1;

  encode_packet #(
      .TOKEN(1)
  ) tx_usb_packet_inst (
      .reset(reset),
      .clock(clock),

      .tx_tvalid_o(svalid),
      .tx_tready_i(sready),
      .tx_tlast_o (slast),
      .tx_tdata_o (sdata),

      .hsk_send_i(hsend),
      .hsk_done_o(hdone),
      .hsk_type_i(htype),

      .tok_send_i(ksend),
      .tok_done_o(kdone),
      .tok_type_i(ktype),
      .tok_data_i(kdata),

      .trn_tsend_i (tstart),
      .trn_ttype_i (ttype),
      .trn_tdone_o (tdone),
      .trn_tvalid_i(tvalid),
      .trn_tready_o(tready),
      .trn_tlast_i (tlast),
      .trn_tdata_i (tdata)
  );

  decode_packet rx_usb_packet_inst (
      .reset(reset),
      .clock(clock),

      // USB packet-decoder status flags
      .usb_sof_o(usb_sof),
      .crc_err_o(crc_err),

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


  // -- USB configuration endpoint -- //

  localparam [63:0] SERIAL_NUMBER = "GULP2023";
  localparam [7:0] SERIAL_LENGTH = 8;

  localparam [15:0] VENDOR_ID = 16'hF4CE;
  localparam [151:0] VENDOR_STRING = "University of Otago";
  localparam [7:0] VENDOR_LENGTH = 19;

  localparam [15:0] PRODUCT_ID = 16'h0003;
  localparam [63:0] PRODUCT_STRING = "TART USB";
  localparam [7:0] PRODUCT_LENGTH = 8;

  // todo:
  //  - this module is messy -- does it work well enough?
  //  - does wrapping in skid-buffers break it !?
  ctl_pipe0 #(
      .VENDOR_ID(VENDOR_ID),
      .MANUFACTURER_LEN(VENDOR_LENGTH),
      .MANUFACTURER(VENDOR_STRING),
      .PRODUCT_ID(PRODUCT_ID),
      .PRODUCT_LEN(PRODUCT_LENGTH),
      .PRODUCT(PRODUCT_STRING),
      .SERIAL_LEN(SERIAL_LENGTH),
      .SERIAL(SERIAL_NUMBER),
      // .CONFIG_DESC_LEN(CONFIG_DESC_LEN),
      // .CONFIG_DESC(CONFIG_DESC),
      .HIGH_SPEED(1)
  ) U_CFG_PIPE0 (
      .clock(clock),
      .reset(reset),

      .select_i(ctl0_select_w),
      .accept_o(ctl0_accept_w),
      .error_o (ctl0_error_w),

      .usb_addr_o  (usb_addr_w),
      .usb_conf_o  (usb_conf_w),
      .configured_o(usb_configured_w),

      .req_type_i (ctl_rx_rtype_w),
      .req_args_i (ctl_rx_rargs_w),
      .req_value_i(ctl_rx_value_w),

      .m_tvalid_o(cfgi_tvalid_w),
      .m_tready_i(cfgi_tready_w),
      .m_tlast_o (cfgi_tlast_w),
      .m_tdata_o (cfgi_tdata_w)
  );


  //
  //  Core Under New Test
  ///

  transaction #(
      .EP1_BULK_IN (1),  // IN- & OUT- for TART raw (antenna) samples
      .EP1_BULK_OUT(1),
      .EP1_CONTROL (0),
      .EP2_BULK_IN (1),  // IN-only for TART correlated values
      .EP2_BULK_OUT(0),
      .EP2_CONTROL (1),  // Control EP for configuring TART
      .HIGH_SPEED  (1)
  ) U_USB_CONTROL (
      .clock(clock),
      .reset(reset),

      // Configured USB device-address
      .usb_addr_i(usb_addr_w),

      // Signals from the USB packet decoder (upstream)
      .tok_recv_i(tok_recv_w),
      .tok_type_i(tok_type_w),
      .tok_addr_i(tok_addr_w),
      .tok_endp_i(tok_endp_w),

      .hsk_recv_i(rx_hrecv_w),
      .hsk_type_i(rx_htype_w),
      .hsk_send_o(tx_hsend_w),
      .hsk_sent_i(tx_hsent_w),
      .hsk_type_o(tx_htype_w),

      // DATA0/1 info from the decoder, and to the encoder
      .usb_recv_i(usb_rx_trecv_w),
      .usb_type_i(usb_rx_ttype_w),
      .usb_send_o(usb_tx_tsend_w),
      .usb_sent_i(usb_tx_tsent_w),
      .usb_type_o(usb_tx_ttype_w),

      // USB control & bulk data received from host (via decoder)
      .usb_tvalid_i(usb_rx_tvalid_w),
      .usb_tready_o(usb_rx_tready_w),
      .usb_tlast_i (usb_rx_tlast_w),
      .usb_tdata_i (usb_rx_tdata_w),

      // USB control & bulk data transmitted to host (via encoder)
      .usb_tvalid_o(usb_tx_tvalid_w),
      .usb_tready_i(usb_tx_tready_w),
      .usb_tlast_o (usb_tx_tlast_w),
      .usb_tdata_o (usb_tx_tdata_w),

      .ep0_ce_o(ctl0_select_w),
      .ep1_ce_o(),
      .ep2_ce_o(),

      .blk_start_o (),
      .blk_dtype_o (),
      .blk_done1_i (1'b0),
      .blk_done2_i (1'b0),
      .blk_muxsel_o(),

      .blk_tvalid_o(blko_tvalid_w),
      .blk_tready_i(blko_tready_w),
      .blk_tlast_o (blko_tlast_w),
      .blk_tdata_o (blko_tdata_w),

      .blk_tvalid_i(blki_tvalid_w),
      .blk_tready_o(blki_tready_w),
      .blk_tlast_i (blki_tlast_w),
      .blk_tdata_i (blki_tdata_w),

      .ctl_start_o (ctl_rx_start_w),
      .ctl_rtype_o (ctl_rx_rtype_w),
      .ctl_rargs_o (ctl_rx_rargs_w),
      .ctl_value_o (ctl_rx_value_w),
      .ctl_index_o (ctl_rx_index_w),
      .ctl_length_o(ctl_rx_length_w),

      .ctl_tvalid_o(ctl0_tvalid_w),
      .ctl_tready_i(ctl0_tready_w),
      .ctl_tlast_o (ctl0_tlast_w),
      .ctl_tdata_o (ctl0_tdata_w),

      .ctl_tvalid_i(cfgi_tvalid_w),
      .ctl_tready_o(cfgi_tready_w),
      .ctl_tlast_i (cfgi_tlast_w),
      .ctl_tdata_i (cfgi_tdata_w)
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

      sready <= 1'b1;

      hsend  <= 1'b0;
      htype  <= 2'bx;

      tstart <= 1'b1;
      ttype  <= pid[3:2];
      tvalid <= 1'b1;
      tlast  <= 1'b0;
      tdata  <= $urandom;  // {~pid, pid};

      count  <= len;

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
      sready <= 1'b1;

      ksend  <= 1'b1;
      ktype  <= typ;
      kdata  <= {crc5({epn, adr}), epn, adr};

      @(posedge clock);

      while (ksend || !kdone) begin
        @(posedge clock);

        if (kdone) begin
          ksend <= 1'b0;
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
      sready <= 1'b1;

      hsend  <= 1'b1;
      htype  <= typ;

      @(posedge clock);

      while (hsend || !hdone) begin
        @(posedge clock);

        if (hdone) begin
          hsend <= 1'b0;
        end

        if (svalid && slast) begin
          sready <= 1'b0;
        end
      end

      @(posedge clock);
    end
  endtask  // handshake


endmodule  // transaction_tb
