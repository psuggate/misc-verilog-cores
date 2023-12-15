`timescale 1ns / 100ps
module encode_packet #(
    parameter TOKEN = 0
) (
    input reset,
    input clock,

    output enc_busy_o,

    output tx_tvalid_o,
    input tx_tready_i,
    output tx_tlast_o,
    output [7:0] tx_tdata_o,

    input [1:0] hsk_type_i,  /* 00 - ACK, 10 - NAK, 11 - STALL, 01 - BLYAT */
    input hsk_send_i,
    output hsk_done_o,

    input tok_send_i,
    output tok_done_o,
    input [1:0] tok_type_i,
    input [15:0] tok_data_i,

    // Data transfer properties
    input [1:0] dat_type_i,  /* DATA0/1/2 MDATA */
    input dat_send_i,
    output dat_done_o,

    // AXI4-Stream slave port
    input trn_tvalid_i,
    output trn_tready_o,
    input trn_tlast_i,
    input trn_tkeep_i,
    input [7:0] trn_tdata_i
);


  // -- Module-Wide Definitions -- //

  `include "usb_crc.vh"

  function src_ready(input svalid, input tvalid, input dvalid, input dready);
    src_ready = dready || !(tvalid || (dvalid && svalid));
  endfunction

  function tmp_valid(input svalid, input tvalid, input dvalid, input dready);
    tmp_valid = !src_ready(svalid, tvalid, dvalid, dready);
  endfunction

  function dst_valid(input svalid, input tvalid, input dvalid, input dready);
    dst_valid = tvalid || svalid || (dvalid && !dready);
  endfunction

  function src_to_tmp(input src_ready, input dst_valid, input dst_ready);
    src_to_tmp = src_ready && !dst_ready && dst_valid;
  endfunction

  function tmp_to_dst(input tmp_valid, input dst_ready);
    tmp_to_dst = tmp_valid && dst_ready;
  endfunction

  function src_to_dst(input src_ready, input dst_valid, input dst_ready);
    src_to_dst = src_ready && (dst_ready || !dst_valid);
  endfunction


  localparam [2:0] ST_IDLE = 3'b000;
  localparam [2:0] ST_XHSK = 3'b001;
  localparam [2:0] ST_XTOK = 3'b010;
  localparam [2:0] ST_DATA = 3'b100;

  `define ST_XHSK state[0]
  `define ST_XTOK state[1]
  `define ST_DATA state[2]


  // -- Module State & Signals -- //

  reg xvalid, tvalid, uready, done_q;
  reg xlast, tlast;
  reg [7:0] xdata, tdata;
  wire tvalid_next, xvalid_next, uready_next;

  reg [15:0] crc16_q;

  reg xhsk_q, xtok_q, xdat_q, zero_q, xcrc_q, xsrc_q;
  reg hend_q, kend_q;


  assign enc_busy_o   = tvalid;

  assign hsk_done_o   = hend_q;
  assign tok_done_o   = TOKEN ? kend_q : 1'b0;

  assign tx_tvalid_o  = tvalid;
  assign tx_tlast_o   = tlast;
  assign tx_tdata_o   = tdata;

  assign dat_done_o  = done_q;
  assign trn_tready_o = uready;


  // -- Tx data CRC Calculation -- //

  wire [15:0] crc16_nw;

  genvar ii;
  generate
    for (ii = 0; ii < 16; ii++) begin : g_crc16_revneg
      assign crc16_nw[ii] = ~crc16_q[15-ii];
    end  // g_crc16_revneg
  endgenerate

  always @(posedge clock) begin
    if (!xdat_q) begin
      crc16_q <= 16'hFFFF;
    end else if (trn_tvalid_i && uready) begin
      crc16_q <= crc16(trn_tdata_i, crc16_q);
    end
  end


  // -- ACKs for Handshakes and Tokens -- //

  always @(posedge clock) begin
    if (!hsk_send_i) begin
      hend_q <= 1'b0;
    end else if (xhsk_q && hsk_send_i && tx_tready_i) begin
      hend_q <= 1'b1;
    end else begin
      hend_q <= hend_q;
    end
  end

  always @(posedge clock) begin
    if (!TOKEN || !tok_send_i) begin
      kend_q <= 1'b0;
    end else if (xtok_q && tok_send_i && tlast && tx_tready_i) begin
      kend_q <= 1'b1;
    end else begin
      kend_q <= kend_q;
    end
  end

  // Signals that a packet has been encoded (to the ULPI interface)
  always @(posedge clock) begin
    done_q <= `ST_DATA & tvalid & tlast & tx_tready_i;
  end


  // -- Skid-Register for AXI-S Transfers -- //

  assign uready_next = src_ready(trn_tvalid_i, xvalid, tvalid, tx_tready_i);
  assign xvalid_next = tmp_valid(trn_tvalid_i, xvalid, tvalid, tx_tready_i);
  assign tvalid_next = dst_valid(trn_tvalid_i, xvalid, tvalid, tx_tready_i);

  always @(posedge clock) begin
    // Asserts until we have received the desired data from upstream
    // if (reset || !trn_tvalid_i || trn_tvalid_i && trn_tlast_i && uready) begin
    if (reset || trn_tvalid_i && trn_tlast_i && uready) begin
      xsrc_q <= 1'b0;
    end else if (dat_send_i && !tvalid) begin
      xsrc_q <= 1'b1;
    end else if (!trn_tvalid_i) begin
      // Starvation !!
      xsrc_q <= 1'b0;
    end

    if (!trn_tvalid_i && !dat_send_i || trn_tvalid_i && trn_tlast_i && uready) begin
      // if (!trn_tvalid_i || trn_tvalid_i && trn_tlast_i && uready) begin
      uready <= 1'b0;
    end else if (xdat_q) begin
      uready <= xsrc_q && uready_next;
    end else if (dat_send_i) begin
      uready <= !trn_tlast_i;
    end
    xvalid <= xvalid_next;

    if (src_to_tmp(uready, tvalid, tx_tready_i)) begin
      xdata <= trn_tdata_i;
      xlast <= trn_tlast_i;
    end
  end


  // -- FSM -- //

  wire [2:0] state = {xdat_q, xtok_q, xhsk_q};

  wire zero_data_xfer = trn_tlast_i && trn_tvalid_i && !trn_tkeep_i;

  always @(posedge clock) begin
    if (reset) begin
      {xdat_q, xtok_q, xhsk_q} <= ST_IDLE;
      {zero_q, xcrc_q} <= 2'b00;

      tvalid <= 1'b0;
      tlast <= 1'b0;
      tdata <= 8'bx;
    end else begin
      case (state)
        default: begin  // ST_IDLE
          if (hsk_send_i) begin
            // Perform a single-byte Handshake Transfer
            {xdat_q, xtok_q, xhsk_q} <= ST_XHSK;
            {zero_q, xcrc_q} <= 2'b00;

            tvalid <= 1'b1;
            tlast <= 1'b1;
            tdata <= {~{hsk_type_i, 2'b10}, hsk_type_i, 2'b10};
          end else if (TOKEN && tok_send_i) begin
            // Send a USB Token to a Device
            // Note: Host- & Hub- only
            {xdat_q, xtok_q, xhsk_q} <= ST_XTOK;
            {zero_q, xcrc_q} <= 2'b10;

            tvalid <= 1'b1;
            tlast <= 1'b0;
            tdata <= {~{tok_type_i, 2'b01}, {tok_type_i, 2'b01}};
          end else if (dat_send_i) begin
            // Send a DATA0/1/2 MDATA packet
            {xdat_q, xtok_q, xhsk_q} <= ST_DATA;
            {zero_q, xcrc_q} <= {zero_data_xfer, 1'b0};  // PID-only packet ??

            tvalid <= 1'b1;
            tlast <= 1'b0;
            tdata <= {~{dat_type_i, 2'b11}, {dat_type_i, 2'b11}};
          end else begin
            {xdat_q, xtok_q, xhsk_q} <= ST_IDLE;
            {zero_q, xcrc_q} <= 2'b00;

            tvalid <= 1'b0;
            tlast <= 1'b0;
            tdata <= 8'bx;
          end
        end

        ST_XHSK: begin
          // Handshake packet
          if (!hsk_send_i) begin
            xhsk_q <= 1'b0;
          end

          if (tx_tready_i) begin
            tvalid <= 1'b0;
            tlast  <= 1'b0;
          end

          zero_q <= 1'bx;
          xcrc_q <= 1'bx;
        end

        ST_XTOK: begin
          // Token packet
          if (!tok_send_i) begin
            xtok_q <= 1'b0;
          end

          if (tx_tready_i) begin
            zero_q <= 1'b0;

            if (zero_q) begin
              tvalid <= 1'b1;
              tlast  <= 1'b0;
              tdata  <= tok_data_i[7:0];
            end else if (tlast) begin
              tvalid <= 1'b0;
              tlast  <= 1'b0;
              tdata  <= 8'bx;
            end else begin
              tvalid <= 1'b1;
              tlast  <= 1'b1;
              tdata  <= tok_data_i[15:8];
            end
          end else begin
            zero_q <= zero_q;
          end

          xcrc_q <= 1'bx;
        end

        ST_DATA: begin
          if (xcrc_q && tx_tready_i) begin
            // Sending 2nd byte of CRC16
            if (tlast) begin
              {xdat_q, zero_q, xcrc_q} <= 3'b000;

              tvalid <= 1'b0;
              tlast <= 1'b0;
              tdata <= 8'bx;
            end else begin
              {xdat_q, zero_q, xcrc_q} <= 3'b101;

              tvalid <= 1'b1;
              tlast <= 1'b1;
              tdata <= crc16_nw[15:8];
            end
          end else if (tx_tready_i && (zero_q || !trn_tvalid_i && !xvalid)) begin
            // Sending 1st byte of CRC16
            {xdat_q, zero_q, xcrc_q} <= 3'b101;

            tvalid <= 1'b1;
            tlast <= 1'b0;
            tdata <= crc16_nw[7:0];
          end else begin
            // Transfer data from source to destination
            xdat_q <= 1'b1;
            tvalid <= tvalid_next;

            if (src_to_dst(uready, tvalid, tx_tready_i)) begin
              zero_q <= trn_tlast_i;
              xcrc_q <= 1'b0;
              tdata  <= trn_tdata_i;
            end else if (tmp_to_dst(xvalid, tx_tready_i)) begin
              zero_q <= xlast;
              xcrc_q <= 1'b0;
              tdata  <= xdata;
            end else begin
              zero_q <= zero_q;
              xcrc_q <= xcrc_q;
              tdata  <= tdata;
            end
          end
        end
      endcase
    end
  end


  // -- Simulation Only -- //

  `ifdef __icarus

  always @(posedge clock) begin
    if (reset) begin
    end else begin
      if (trn_tvalid_i && !trn_tkeep_i && trn_tlast_i) begin
        $error("USB encoder only supports TKEEP=0 for zero-data packets");
      end
    end
  end

  `endif


endmodule  // encode_packet
