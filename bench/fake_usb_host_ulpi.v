`timescale 1ns / 100ps
module fake_usb_host_ulpi (
    clock,
    reset,
    enable,

    ulpi_clock_o,
    ulpi_rst_ni,
    ulpi_dir_o,
    ulpi_nxt_o,
    ulpi_stp_i,
    ulpi_data_io,

    usb_sof_o,
    crc_err_o,
    dev_enum_start_i, 
dev_configured_i,
    dev_enum_done_o

);

  input clock;
  input reset;
  input enable;

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
  input dev_configured_i;
  output dev_enum_done_o;


  // -- Constants & Settings -- //

  `include "usb_crc.vh"

  localparam HIGH_SPEED = 1;
  localparam TOKEN = 1;

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam DATA0 = 2'b00;
  localparam DATA1 = 2'b10;


  // -- State & Signals -- //

  reg enum_done_q;

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

  wire [1:0] usb_rx_ttype_w;
  wire tdone;

  wire tok_recv_w, rx_hrecv_w;
  wire [1:0] tok_type_w, rx_htype_w;
  wire [6:0] tok_addr_w;
  wire [3:0] tok_endp_w;


  // -- Input/Output Assignments -- //

  assign dev_enum_done_o = enum_done_q;


  // -- Fake Stimulus -- //

  initial begin : g_stimulus
    tvalid <= 1'b0;
    tlast <= 1'b0;

    hsend_q <= 1'b0;
    ksend_q <= 1'b0;

    @(posedge clock);
    while (!enable) begin
      @(posedge clock);
    end

    #80
    while (state != ST_ENUM) begin
      @(posedge clock);
    end

    @(posedge clock);
    // Default ADDR, Pipe0 ENDP, SETUP, Device Req, Set Addr, New ADDR
    send_control(7'h00, 4'h0, 8'h00, 8'h05, 16'h0009);

    while (!dev_configured_i) begin
      @(posedge clock);
    end

    @(posedge clock);
    $display("%10t: USB configured", $time);
  end


  // -- Fake ULPI -- //

  localparam ST_INIT = 4'h0;
  localparam ST_ENUM = 4'h2;
  localparam ST_IDLE = 4'hf;

  reg [3:0] state;

  always @(posedge clock) begin
    if (reset || !ulpi_rst_ni) begin
      state <= ST_INIT;
      enum_done_q <= 1'b0;

      sready  <= 1'b0;
      mvalid  <= 1'b0;
    end else begin
      case (state)
        ST_INIT: begin
          if (dev_enum_start_i) begin
            state <= ST_ENUM;
          end
        end

        ST_ENUM: begin
          // send_token(TOK_SETUP);
          if (dev_configured_i) begin
            state <= ST_IDLE;
          end
        end

        default: begin
        end
      endcase
    end
  end


  assign usb_rx_tready_w = 1'b1;

  fake_ulpi_phy U_ULPI_PHY0 (
      .clock(clock),
      .reset(reset),

      .ulpi_clock_o(ulpi_clock_o),
      .ulpi_rst_ni (ulpi_rst_ni),
      .ulpi_dir_o  (ulpi_dir_o),
      .ulpi_nxt_o  (ulpi_nxt_o),
      .ulpi_stp_i  (ulpi_stp_i),
      .ulpi_data_io(ulpi_data_io),

      // From the USB packet encoder
      .usb_tvalid_i(usb_tx_tvalid_w),
      .usb_tready_o(usb_tx_tready_w),
      .usb_tlast_i (usb_tx_tlast_w),
      .usb_tdata_i (usb_tx_tdata_w),

      // To the USB packet decoder
      .usb_tvalid_o(usb_rx_tvalid_w),
      .usb_tready_i(usb_rx_tready_w),
      .usb_tlast_o (usb_rx_tlast_w),
      .usb_tdata_o (usb_rx_tdata_w)
  );


  // -- USB Packet Operations -- //

  encode_packet #(
      .TOKEN(1)
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


  // -- USB OUT Control Transfer -- //

  task send_control;
    input [6:0] addr;
    input [3:0] endp;
    input [7:0] rtype;
    input [7:0] rargs;
    input [15:0] value;
    begin
      reg [63:0] data;
      data <= {16'h0, 16'h0, value, rargs, rtype};

      send_token(addr, endp, TOK_SETUP);
      $display("%10t: SETUP token sent", $time);
      send_data0(data);
      recv_ack();

      recv_data1();
      send_ack();
      @(posedge clock);
    end
  endtask // send_control
  
  // Encode and send a USB 'DATA0' packet
  task send_data0;
    input [63:0] data;
    begin
      integer count;

      {tstart, ttype} <= {1'b1, DATA0};
      {tvalid, tlast} <= 2'b10;
      {data, tdata} <= {8'hxx, data};
      count <= 7;

      while (!tdone) begin
        @(posedge clock);
        tstart <= 1'b0;

        if (tvalid && tready) begin
          {tvalid, tlast} <= {count > 0, count == 1};
          {data, tdata} <= {8'hxx, data};
          count <= count - 1;
        end
      end

      @(posedge clock);
      $display("%10t: DATA0 packet sent (bytes: 8)", $time);
    end
  endtask // send_data0

  // Receive and decode a USB 'DATA1' packet
  task recv_data1;
    begin
      integer count;

      count <= 0;
      sready <= 1'b1;
      while (!svalid) @(posedge clock);

      if (sdata != {~{DATA1, 2'b11}, {DATA1, 2'b11}}) begin
        $error("%10t: Not a DATA1 packet: %02x", $time, sdata);
        #100 $fatal;
      end

      while (svalid && !slast) begin
        @(posedge clock);
        if (svalid) count <= count + 1;
        sready <= !(svalid && slast);
      end

      @(posedge clock);
      $display("%10t: DATA1 packet received (bytes: %2d)", $time, count);
    end
  endtask // recv_data1


  // -- Encode and Send a USB Token Packet -- //

  task send_token;
    input [6:0] adr;
    input [3:0] epn;
    input [1:0] typ;
    begin
      reg [7:0] pid;

      sready  <= 1'b1;
      ksend_q <= 1'b1;
      ktype_q <= typ;
      pid <= {~{typ, 2'b01}, {typ, 2'b01}};
      kdata_q <= {crc5({epn, adr}), epn, adr};

      @(posedge clock);
      $display("%10t: Sending token: [0x%02x, 0x%02x, 0x%02x]", $time, pid, kdata_q[7:0], kdata_q[15:8]);

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


  // -- Encode and Send a USB Handshake Packet -- //

  // Send a USB 'ACK' handshake packet
  task send_ack;
    begin
      handshake(HSK_ACK);
      $display("%10t: ACK sent", $time);
    end
  endtask // send_ack

  // Receive a USB 'ACK' handshake packet
  task recv_ack;
    begin
      while (!rx_hrecv_w || rx_htype_w != HSK_ACK) @(posedge clock);
      @(posedge clock);
      $display("%10t: ACK received", $time);
    end
  endtask // recv_ack

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


endmodule  // fake_usb_host_ulpi
