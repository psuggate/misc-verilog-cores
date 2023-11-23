`timescale 1ns / 100ps
module encode_packet_tb;

  // -- Simulation Data -- //

  `include "usb_crc.vh"

  initial begin
    $dumpfile("encode_packet_tb.vcd");
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


  // -- Test-Module Output Checker -- //

  wire trn_start, mvalid, mready, mend;
  wire [1:0] trn_type, mtype;
  wire usb_sof, crc_err, hrecv;
  wire [6:0] trn_address, usb_address;
  wire [3:0] trn_endpoint;
  wire [7:0] mdata;

  assign usb_address = 7'h00;

  decode_packet rx_usb_packet_inst (
      .reset(reset),
      .clock(clock),

      .rx_tvalid_i(svalid),
      .rx_tready_o(mready),
      .rx_tlast_i (slast),
      .rx_tdata_i (sdata),

      .trn_start_o(trn_start),
      .trn_type_o(trn_type),
      .trn_address_o(trn_address),
      .trn_endpoint_o(trn_endpoint),
      .usb_address_i(usb_address),

      .usb_sof_o(usb_sof),
      .crc_err_o(crc_err),

      .rx_trn_valid_o(mvalid),
      .rx_trn_end_o  (mend),
      .rx_trn_type_o (mtype),
      .rx_trn_data_o (mdata),

      .trn_hsk_type_o(),
      .trn_hsk_recv_o(hrecv)
  );


  //
  //  Core Under New Test
  ///

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

      .trn_start_i (tstart),
      .trn_type_i  (ttype),
      .trn_tvalid_i(tvalid),
      .trn_tready_o(tready),
      .trn_tlast_i (tlast),
      .trn_tdata_i (tdata)
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
      integer count;

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


endmodule  // encode_packet_tb
