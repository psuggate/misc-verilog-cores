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

  localparam [15:0] LANG_EN_US = {8'h4, 8'h9};

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam DATA0 = 2'b00;
  localparam DATA1 = 2'b10;

  // USB device configuration address
  localparam [6:0] DEV_ADDR = 7'h09;


  // -- State & Signals -- //

  reg enum_done_q, desc_done_q, conf_done_q, str0_done_q, blko_done_q;
  reg blki_done_q, tele_done_q, prod_done_q;
  wire [6:0] dev_addr_w;

  reg mvalid, sready, hsend, tstart, tvalid, tkeep, tlast;
  wire srecv, svalid, mready, slast, hdone, tready;
  reg [1:0] htype, ttype;
  reg  [7:0] tdata;
  wire [1:0] stype;
  wire [7:0] sdata;

  reg hsend_q, ksend_q;
  reg [1:0] htype_q, ktype_q;
  reg [15:0] kdata_q;
  wire hdone_w, kdone_w;

  wire usb_rx_tvalid_w, usb_rx_tready_w, usb_rx_tlast_w;
  wire usb_tx_tvalid_w, usb_tx_tready_w, usb_tx_tlast_w;
  wire ulpi_rx_tvalid_w, ulpi_rx_tready_w, ulpi_rx_tlast_w;
  wire [7:0] usb_rx_tdata_w, usb_tx_tdata_w, ulpi_rx_tdata_w;

  wire [1:0] usb_rx_ttype_w;
  wire tbusy, tdone;

  wire tok_recv_w, rx_hrecv_w;
  wire [1:0] tok_type_w, rx_htype_w;
  wire [6:0] tok_addr_w;
  wire [3:0] tok_endp_w;


  // -- Input/Output and Signal Assignments -- //

  assign dev_enum_done_o = enum_done_q;

  assign dev_addr_w = dev_configured_i ? DEV_ADDR : 7'h00;


  // -- Fake Stimulus -- //

  initial begin : g_startup
    {tvalid, tlast} <= 2'b00;
    {hsend_q, ksend_q} <= 2'b00;
    enabled();
    $display("%10t: DEVICE has ENABLE asserted", $time);
  end

  // Read the device-configuration descriptor
  initial begin : g_read_desc
    enabled();
    #80 while (state != ST_DESC) @(posedge clock);

    $display("%10t: FETCH device DESCRIPTOR", $time);
    recv_control(7'h00, 4'h0, 8'h80, 8'h06, {8'h01, 8'h00}, 16'h0, 64);

    $display("%10t: FETCH config DESCRIPTOR (9 bytes)", $time);
    recv_control(7'h00, 4'h0, 8'h80, 8'h06, {8'h02, 8'h00}, 16'h0, 9);
    $display("%10t: FETCH config DESCRIPTOR (39 bytes)", $time);
    recv_control(7'h00, 4'h0, 8'h80, 8'h06, {8'h02, 8'h00}, 16'h0, 39);
    desc_done_q <= 1'b1;

    @(posedge clock);
    $display("%10t: DESCRIPTOR from device ...", $time);
  end

  // Set the device-address of a USB device
  initial begin : g_enumerate
    enabled();
    #80 while (state != ST_ENUM) @(posedge clock);

    // Default ADDR, Pipe0 ENDP, SETUP, Device Req, Set Addr, New ADDR
    $display("%10t: Enumerating USB device address", $time);
    send_address(DEV_ADDR);

    send_sof(11'h123);

    // USB device has been enumerated (received a device-address)
    @(posedge clock);
    enum_done_q <= 1'b1;

    @(posedge clock);
    $display("%10t: USB enumerated", $time);
  end

  // Enable a device configuration
  initial begin : g_configure
    enabled();
    #80 while (state != ST_CONF) @(posedge clock);

    // Default ADDR, Pipe0 ENDP, SETUP, Device Req, Set Addr, New ADDR
    $display("%10t: Setting USB device configuration", $time);
    send_control(DEV_ADDR, 4'h0, 8'h00, 8'h09, 16'h0001, 16'h0);

    while (!dev_configured_i) @(posedge clock);
    @(posedge clock);
    conf_done_q <= 1'b1;

    @(posedge clock);
    $display("%10t: USB configured", $time);
  end

  // Read the STRING DESCRIPTOR for the serial-number, from the device
  initial begin : g_read_serial
    enabled();
    #80 while (!conf_done_q) @(posedge clock);
    #80 while (state != ST_STR0) @(posedge clock);

    $display("%10t: FETCH device SERIAL#", $time);
    recv_control(DEV_ADDR, 4'h0, 8'h80, 8'h06, {8'h03, 8'h03}, LANG_EN_US, 64);
    str0_done_q <= 1'b1;

    $display("%10t: SERIAL from device ...", $time);
  end

  initial begin : g_bulk_out
    enabled();
    #80 while (state != ST_BLKO) @(posedge clock);

    #80 $display("%10t: BULK data OUT", $time);
    send_token(DEV_ADDR, 4'h1, TOK_OUT);
    send_data({$urandom, $urandom}, 3'd7, 0);
    recv_ack();
    blko_done_q <= 1'b1;

    $display("%10t: BULK data OUT finished ...", $time);
  end

  initial begin : g_bulk_in
    enabled();
    #80 while (state != ST_BLKI) @(posedge clock);

    #80 $display("%10t: BULK data IN", $time);
    send_token(DEV_ADDR, 4'h1, TOK_IN);
    recv_data1();
    send_ack();

    #80 $display("%10t: BULK data IN", $time);
    send_token(DEV_ADDR, 4'h1, TOK_IN);
    recv_data0();
    send_ack();
    blki_done_q <= 1'b1;

    $display("%10t: BULK data IN finished ...", $time);
  end

  initial begin : g_telemetry
    enabled();
    #80 while (state != ST_TELE) @(posedge clock);

    #80 $display("%10t: Telemetry data IN", $time);
    send_token(DEV_ADDR, 4'h2, TOK_IN);
    recv_data0();
    send_ack();
    tele_done_q <= 1'b1;

    $display("%10t: Telemetry data IN finished ...", $time);
  end

  //
  //  Moar
  ///
  initial begin : g_product_string
    enabled();
    #80 while (state != ST_PROD) @(posedge clock);

    $display("%10t: FETCH STRING DESCRIPTOR (0)", $time);
    recv_control(DEV_ADDR, 4'h0, 8'h80, 8'h06, {8'h03, 8'h00}, 16'h0, 4);

    $display("%10t: STRING LANGUAGE = todo ...", $time);

    $display("%10t: FETCH PRODUCT STRING", $time);
    recv_control(DEV_ADDR, 4'h0, 8'h80, 8'h06, {8'h03, 8'h02}, LANG_EN_US, 255);
    prod_done_q <= 1'b1;

    $display("%10t: FETCH PRODUCT STRING finished ...", $time);
  end


  // -- Fake ULPI -- //

  localparam ST_INIT = 4'h0;
  localparam ST_DESC = 4'h1;
  localparam ST_ENUM = 4'h2;
  localparam ST_CONF = 4'h3;
  localparam ST_STR0 = 4'h4;
  localparam ST_BLKO = 4'h5;
  localparam ST_BLKI = 4'h6;
  localparam ST_TELE = 4'h7;
  localparam ST_PROD = 4'h8;
  localparam ST_IDLE = 4'hf;

  reg [3:0] state;

  always @(posedge clock) begin
    if (reset || !ulpi_rst_ni) begin
      state <= ST_INIT;
      desc_done_q <= 1'b0;
      enum_done_q <= 1'b0;
      conf_done_q <= 1'b0;
      str0_done_q <= 1'b0;
      blko_done_q <= 1'b0;
      blki_done_q <= 1'b0;
      tele_done_q <= 1'b0;
      prod_done_q <= 1'b0;

      sready <= 1'b0;
      mvalid <= 1'b0;
    end else begin
      case (state)
        ST_INIT: state <= dev_enum_start_i ? ST_DESC : state;
        ST_DESC: state <= desc_done_q ? ST_ENUM : state;
        ST_ENUM: state <= enum_done_q ? ST_CONF : state;
        ST_CONF: state <= conf_done_q ? ST_STR0 : state;
        ST_STR0: state <= str0_done_q ? ST_BLKO : state;
        ST_BLKO: state <= blko_done_q ? ST_BLKI : state;
        ST_BLKI: state <= blki_done_q ? ST_TELE : state;
        ST_TELE: state <= tele_done_q ? ST_PROD : state;
        ST_PROD: state <= prod_done_q ? ST_IDLE : state;
        default: begin
          // $display("%10t: Hello!", $time);
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
      .usb_tvalid_o(ulpi_rx_tvalid_w),
      .usb_tready_i(ulpi_rx_tready_w),
      .usb_tlast_o (ulpi_rx_tlast_w),
      .usb_tdata_o (ulpi_rx_tdata_w)
  );


  // -- USB Packet Operations -- //

  encode_packet #(
      .TOKEN(1)
  ) U_TX_USB_PACKET0 (
      .reset(reset),
      .clock(clock),

      .enc_busy_o(tbusy),

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

      .dat_send_i(tstart),
      .dat_type_i(ttype),
      .dat_done_o(tdone),

      .trn_tvalid_i(tvalid),
      .trn_tready_o(tready),
      .trn_tkeep_i (tkeep),
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
      .ulpi_tvalid_i(ulpi_rx_tvalid_w),
      .ulpi_tready_o(ulpi_rx_tready_w),
      .ulpi_tlast_i (ulpi_rx_tlast_w),
      .ulpi_tdata_i (ulpi_rx_tdata_w),

      // Indicates that a (OUT/IN/SETUP) token was received
      .tok_recv_o(tok_recv_w),
      .tok_type_o(tok_type_w),
      .tok_addr_o(tok_addr_w),
      .tok_endp_o(tok_endp_w),

      // Data packet (OUT, DATA0/1/2 MDATA) received
      .out_recv_o  (srecv),
      .out_type_o  (stype),
      .out_tvalid_o(svalid),
      .out_tready_i(sready),
      .out_tlast_o (slast),
      .out_tdata_o (sdata),

      // Handshake packet information
      .hsk_type_o(rx_htype_w),
      .hsk_recv_o(rx_hrecv_w)
  );


  //
  //  Simulation Tasks
  ///

  // Blocks until this module has been enabled
  task enabled;
    begin
      @(posedge clock);
      while (!enable) begin
        @(posedge clock);
      end
    end
  endtask  // enable


  // -- Encode and Send a USB Handshake Packet -- //

  // Send a USB 'ACK' handshake packet
  task send_ack;
    begin
      handshake(HSK_ACK);
      $display("%10t: ACK sent", $time);
    end
  endtask  // send_ack

  // Receive a USB 'ACK' handshake packet
  task recv_ack;
    begin
      while (!rx_hrecv_w || rx_htype_w != HSK_ACK) @(posedge clock);
      $display("%10t: ACK received", $time);
    end
  endtask  // recv_ack

  // Send a USB handshake response
  task handshake;
    input [1:0] typ;
    begin
      {hsend_q, htype_q} <= {1'b1, typ};
      @(posedge clock);

      while (hsend_q || !hdone_w) begin
        @(posedge clock);
        if (hdone_w) hsend_q <= 1'b0;
      end
    end
  endtask  // handshake


  // -- Encode and Send a USB Token Packet -- //

  task send_token;
    input [6:0] adr;
    input [3:0] epn;
    input [1:0] typ;
    begin
      reg [7:0] pid;

      pid <= {~{typ, 2'b01}, {typ, 2'b01}};
      {ksend_q, ktype_q, kdata_q} <= {1'b1, typ, {crc5({epn, adr}), epn, adr}};
      @(posedge clock);
      $display("%10t: Sending token: [0x%02x, 0x%02x, 0x%02x]", $time, pid, kdata_q[7:0],
               kdata_q[15:8]);

      while (ksend_q || !kdone_w) begin
        @(posedge clock);
        if (kdone_w) ksend_q <= 1'b0;
      end
    end
  endtask  // send_token

  task send_setup;
    input [6:0] addr;
    input [3:0] endp;
    input [63:0] data;
    begin
      send_token(addr, endp, TOK_SETUP);
      $display("%10t: SETUP token sent", $time);
      send_data0(data);
      recv_ack();
    end
  endtask  // send_setup

  task send_sof;
    input [10:0] num;
    begin
      send_token(num[6:0], num[10:7], TOK_SOF);
      $display("%10t: SOF token sent", $time);
    end
  endtask  // send_sof


  // -- USB Control Transfers -- //

  reg [8:0] resp[0:1023];

  task recv_status;
    input [6:0] addr;
    input [3:0] endp;
    begin
      send_token(addr, endp, TOK_IN);
      $display("%10t: Waiting for STATUS IN", $time);
      recv_data1();
      $display("%10t: STATUS received", $time);
      send_ack();
    end
  endtask  // recv_status

  // Enumerate a USB device's address
  task send_address;
    input [6:0] addr;
    begin
      send_setup(7'h00, 4'h0, {16'h0, 16'h0, {9'h000, addr}, 8'h05, 8'h00});
      $display("%10t: ADDRESS enumeration ('%02x') sent", $time, addr);
      recv_status(addr, 4'h0);
    end
  endtask  // send_control

  // Control Transfer to a USB device  
  task send_control;
    input [6:0] addr;
    input [3:0] endp;
    input [7:0] rtype;
    input [7:0] rargs;
    input [15:0] value;
    input [15:0] index;
    begin
      send_setup(addr, endp, {16'h0, index, value, rargs, rtype});
      recv_status(addr, endp);
    end
  endtask  // send_control

  // Request configuration/control information from a USB device
  task recv_control;
    input [6:0] addr;
    input [3:0] endp;
    input [7:0] rtype;
    input [7:0] rargs;
    input [15:0] value;
    input [15:0] index;
    input [7:0] length;
    begin
      reg [63:0] data;
      // Note: Control Transfer IN packet-size is 64B (High-Speed)
      // Note: Control Transfer IN packet-size when reading STRING DESCRIPTORs
      //  is 255B (High-Speed)
      send_setup(addr, endp, {{8'h0, length}, index, value, rargs, rtype});

      send_token(addr, endp, TOK_IN);  // Data Stage
      recv_data1();
      send_ack();

      send_token(addr, endp, TOK_OUT);  // Status Stage
      send_data(0, 0, 1);
      recv_ack();
    end
  endtask  // recv_control


  // -- USB Data Transfers -- //

  task send_data;
    input [63:0] data;
    input [2:0] len;
    input odd;
    begin
      integer count;

      {tstart, ttype} <= {1'b1, odd ? DATA1 : DATA0};
      {tvalid, tlast} <= {len != 0, len == 0};
      {data, tdata} <= {8'hxx, data};
      count <= len;

      while (!tdone) begin
        @(posedge clock);
        tstart <= 1'b0;

        if (tvalid && tready) begin
          {tvalid, tlast} <= {count > 0, count == 1};
          {data, tdata} <= {8'hxx, data};
          count <= count - 1;
        end
      end
      $display("%10t: DATA0 packet sent (bytes: 8)", $time);
    end
  endtask  // send_data

  // Encode and send a USB 'DATA0' packet (8 bytes)
  task send_data0;
    input [63:0] data;
    begin
      send_data(data, 3'd7, 0);
    end
  endtask  // send_data0

  // Encode and send a USB 'DATA1' packet (8 bytes)
  task send_data1;
    input [63:0] data;
    begin
      send_data(data, 3'd7, 1);
    end
  endtask  // send_data1

  // Receive and decode USB 'DATA0/1' packets
  task recv_data;
    input odd;
    begin
      integer count;
      count  <= 0;
      sready <= 1'b1;
      while (!srecv) @(posedge clock);
      @(posedge clock);

      if (odd && stype != DATA1 || !odd && stype != DATA0) begin
        $error("%10t: Not a DATA%1d packet: 0x%02x", $time, odd, stype);
        #100 $fatal;
      end

      while (!slast) begin
        @(posedge clock);
        if (svalid) begin
          resp[count] <= {slast, sdata};
          count <= count + 1;
        end
      end
      sready <= 1'b0;
      count  <= count + (svalid && slast);
      @(posedge clock);
      $display("%10t: DATA%1d packet received (bytes: %2d)", $time, odd, count);
    end
  endtask  // recv_data

  // Receive and decode a USB 'DATA1' packet
  task recv_data1;
    begin
      recv_data(1);
    end
  endtask  // recv_data1

  // Receive and decode a USB 'DATA1' packet
  task recv_data0;
    begin
      recv_data(0);
    end
  endtask  // recv_data0


  // -- Basic, Flow-Control Rules-Checkers -- //

  // Check the output to ULPI-interface module //
  axis_flow_check U_AXIS_FLOW6 (
      .clock(clock),
      .reset(reset),
      .axis_tvalid(usb_tx_tvalid_w),
      .axis_tready(usb_tx_tready_w),
      .axis_tlast(usb_tx_tlast_w),
      .axis_tdata(usb_tx_tdata_w)
  );

  // Check the output from ULPI-interface module //
  axis_flow_check U_AXIS_FLOW7 (
      .clock(clock),
      .reset(reset),
      .axis_tvalid(ulpi_rx_tvalid_w),
      .axis_tready(ulpi_rx_tready_w),
      .axis_tlast(ulpi_rx_tlast_w),
      .axis_tdata(ulpi_rx_tdata_w)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [119:0] dbg_state;

  always @* begin
    case (state)
      ST_INIT: dbg_state = "INIT";
      ST_DESC: dbg_state = "DESC";
      ST_ENUM: dbg_state = "ENUM";
      ST_CONF: dbg_state = "CONF";
      ST_STR0: dbg_state = "STR0";
      ST_BLKO: dbg_state = "BLKO";
      ST_BLKI: dbg_state = "BLKI";
      ST_TELE: dbg_state = "TELE";
      ST_PROD: dbg_state = "PROD";
      ST_IDLE: dbg_state = "IDLE";

      default: dbg_state = "UNKNOWN";
    endcase
  end

`endif


endmodule  // fake_usb_host_ulpi
