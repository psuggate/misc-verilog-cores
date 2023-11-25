`timescale 1ns / 100ps
module transaction (  /*AUTOARG*/);

  parameter EP1_BULK_IN = 1;
  parameter EP1_BULK_OUT = 1;
  parameter EP1_CONTROL = 0;

  parameter EP2_BULK_IN = 1;
  parameter EP2_BULK_OUT = 0;
  parameter EP2_CONTROL = 1;

  parameter ENDPOINT1 = 1;  // set to '0' to disable
  parameter ENDPOINT2 = 2;  // set to '0' to disable

  parameter HIGH_SPEED = 1;


  input clock;
  input reset;

  input [6:0] usb_addr_i;

  // Signals from the USB packet decoder (upstream)
  input tok_recv_i;
  input [1:0] tok_type_i;
  input [6:0] tok_addr_i;
  input [3:0] tok_endp_i;

  input hsk_recv_i;
  input [1:0] hsk_type_i;
  output hsk_sent_o;
  input hsk_sent_i;
  output [1:0] hsk_type_o;

  input out_tvalid_i;
  output out_tready_o;
  input out_tlast_i;
  input [1:0] out_ttype_i;
  input [7:0] out_tdata_i;

  // Signals to the downstream endpoints
  output ep0_ce_o;  // Control EP
  output ep1_ce_o;  // Bulk EP #1
  output ep2_ce_o;  // Bulk EP #2


// -- Module Constants -- //

localparam TOK_OUT   = 2'b00;
localparam TOK_IN    = 2'b10;
localparam TOK_SETUP = 2'b11;


  // -- Input and Output Signal Assignments -- //

  reg ep0_ce_q, ep1_ce_q, ep2_ce_q;


  assign ep0_ce_o = ep0_ce_q;
  assign ep1_ce_o = ep1_ce_q;
  assign ep2_ce_o = ep2_ce_q;


  // -- Downstream Chip-Enables -- //

  always @(posedge clock) begin
    if (reset) begin
      {ep2_ce_q, ep1_ce_q, ep0_ce_q} <= 3'b000;
    end else if (tok_recv_i && tok_addr_i == usb_addr_i) begin
      ep0_ce_q <= tok_type_i == 2'b11 && tok_endp_i == 4'h0;
      ep1_ce_q <= ENDPOINT1 != 0 && tok_endp_i == ENDPOINT1[3:0];
      ep2_ce_q <= ENDPOINT2 != 0 && tok_endp_i == ENDPOINT2[3:0];
    end
  end


  // -- Transaction FSM -- //

  //
  // Hierarchical, pipelined FSM that just enables the relevant lower-level FSM,
  // waits for it to finish, or handles any errors.
  //
  // Todo: should this FSM handle no-data responses ??
  //
  localparam ST_IDLE = 4'h0;
  localparam ST_BULK = 4'h1; // USB Bulk IN/OUT Transfer
  localparam ST_CTRL = 4'h2; // USB Control Transfer
  localparam ST_DUMP = 4'hf; // ignoring xfer, or bad shit happened

  reg [3:0] state, xbulk, xctrl;
  reg blk_start_q, ctl_start_q;
  reg blk_error_q, ctl_error_q;

  // todo: control the input MUX, and the output CE's
  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      ctl_req_type_q <= 3'b000;
    end else begin
      case (state)
        default: begin // ST_IDLE
          //
          // Decode tokens until we see our address, and a valid endpoint
          ///
          if (tok_recv_i && tok_addr_i == usb_addr_i) begin
            if ((tok_type_i == TOK_IN || tok_type_i == TOK_OUT) &&
                (tok_endp_i == ENDPOINT1 || tok_endp_i == ENDPOINT2)) begin
              state <= ST_BULK;
              blk_start_q <= 1'b1;
              ctl_start_q <= 1'b0;
            end else if (tok_type_i == TOK_SETUP &&
                         (tok_endp_i == 4'h0 || // PIPE0 required
                          EP1_CONTROL && tok_endp_i == ENDPOINT1 ||
                          EP2_CONTROL && tok_endp_i == ENDPOINT2)) begin
              state <= ST_CTRL;
              blk_start_q <= 1'b0;
              ctl_start_q <= 1'b1;
            end else begin
              // Either invalid endpoint, or unsupported transfer-type for the
              // requested endpoint.
              state <= ST_DUMP;
              blk_start_q <= 1'b0;
              ctl_start_q <= 1'b0;
            end
          end else begin
            state <= ST_IDLE;
            blk_start_q <= 1'b0;
            ctl_start_q <= 1'b0;
          end
        end

        ST_BULK: begin
          //
          // Wait for the USB to finish, and then return to IDLE
          ///
          if (blk_error_q) begin
            // Bulk Transfer has failed, wait for the USB to settle down
            state <= ST_DUMP;
          else if (xbulk == BLK_IDLE) begin
            state <= ST_IDLE;
          end
        end

        ST_CTRL: begin
          //
          // Wait for the USB to finish, and then return to IDLE
          ///
          if (ctl_error_q) begin
            // Control Transfer has failed, wait for the USB to settle down
            state <= ST_DUMP;
          end else if (xctrl == CTL_IDLE) begin
            state <= ST_IDLE;
          end
        end

        ST_DUMP: begin
          //
          // todo: Wait for the USB to finish, and then return to IDLE
          ///
          state <= 'bx;
        end
      endcase
    end
  end


  // -- FSM for Bulk IN/OUT Transfers to Endpoints -- //

  //
  // Bulk transfers 
  //
  reg blk_hsend_q; // note: just a strobe (for the handshake FSM)
  reg [1:0] blk_htype_q;

  always @(posedge clock) begin
    if (state == ST_BULK) begin
      case (xctrl)
        default: begin
          xctrl <= CTL_IDLE;
          hsend_q <= 1'b0;
          htype_q <= 2'bx;
        end
      endcase
    end else begin
      if (blk_start_q) begin
        xbulk <= BLK_SETUP_DAT;
      end else begin
        xbulk <= CTL_IDLE;
      end
      blk_hsend_q <= 1'b0;
    end
  end


  // -- Control Transfers FSM -- //

  //
  // These transfers have a predefined structure (see pp.225, USB 2.0 Spec), and
  // the initial 'DATA0' packet (after the 'SETUP' token) contains data laid-out
  // in a predefined manner:
  //  - BYTE[0]   -- Request Type
  //  - BYTE[1]   -- Request
  //  - BYTE[3:2] -- Value
  //  - BYTE[5:4] -- Index
  //  - BYTE[7:6] -- Buffer length (can be zero)
  //  - BYTE[8..] -- Buffer contents (optional)
  // After receiving the packets: 'SETUP' & 'DATA0', a USB must respond witn an
  // 'ACK' handshake, before the "Data Stage" of the Control Transfer begins.
  //
  // Post-'ACK', the host issues an 'IN' (or 'OUT') token, and the device (or
  // host, respectively) then follows with zero or more DATA1, DATA0, ... tokens
  // and packets (and with the receiver replying with 'ACK' handshakes).
  //
  // Finally, the "Status Stage" of the Control Transfer requires that a status
  // packet (in the opposite bus direction to the 'DATA0/1' packets) be sent
  // (after the host issues the appropriate 'IN'/'OUT' token, folowed by an 'ACK'
  // handshake) to terminate the Control Transfer. This final packet is always a
  // 'DATA1' packet.
  //
  // Note: the initial 'SETUP' token has been parsed, and used to enable this FSM,
  //   so does not need to be parsed/processed here.
  //
  // Note: the 'DATA0/1' packets are transfered in exactly as the same manner as
  //   for Bulk Transfers, during the "Data Stage," but the first data packet is
  //   always a 'DATA1' (if there is one), following by the usual toggling.
  //

  reg ctl_hsend_q; // note: just a strobe (for the handshake FSM)
  reg [1:0] ctl_htype_q;

  reg [2:0] ctl_req_type_q;
  reg ctl_req_recv_q;

  // todo: recognise control requests to PIPE0
  // todo: then extract the relevant fields
  always @(posedge clock) begin
    if (state == ST_CTRL) begin
      case (xctrl)
        CTL_FAIL: begin
          xctrl <= CTL_IDLE;
          hsend_q <= 1'b0;
          htype_q <= 2'bx;
        end

        default: begin // CTL_SETUP_DAT
          // todo: parse and extract the initial bytes ...

          if (out_tvalid_i && out_tready_o && out_tlast_i) begin
            xctrl <= CTL_SETUP_ACK;
            hsend_q <= 1'b1;
            htype_q <= HSK_ACK;
          end else begin
            xctrl <= xctrl;
            hsend_q <= 1'b0;
            htype_q <= 2'bx;
          end
        end

        CTL_SETUP_ACK: begin
          hsend_q <= 1'b0;
          htype_q <= 2'bx;

          if (hsk_sent_i) begin
            xctrl <= CTL_DATA_OUT_IN;
          end
        end

        // Data:   OUT/IN
        //         DATA1
        //         ACK
        //         DATA0
        //         ACK
        //         ...

        // Status: IN/OUT
        //         DATA1
        //         ACK

        CTL_DONE: begin
          // Wait for the main FSM to return to IDLE, and then get ready for the
          // next Control Transfer.
          if (state == ST_IDLE) begin
            xctrl <= CTL_SETUP_DAT;
          end
        end

      endcase
    end else begin

      // Todo: does not do anything ??
      if (ctl_start_q) begin
        xctrl <= CTL_SETUP_DAT;
      end else begin
        xctrl <= CTL_IDLE;
      end
      ctl_hsend_q <= 1'b0;
    end

  end


  // -- FSM to Issue Handshake Packets -- //

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  reg hsend_q;
  reg [1:0] htype_q;

  assign hsk_send_o = hsend_q;
  assign hsk_type_o = htype_q;

  always @(posedge clock) begin
    if (reset) begin
      hsend_q <= 1'b0;
      htype_q <= 2'bx;
    end else begin
      if (ctl_hsend_q || blk_hsend_q) begin
        hsend_q <= 1'b1;
        htype_q <= ctl_hsend_q ? ctl_htype_q : blk_htype_q;
      end else if (hsk_sent_i) begin
        hsend_q <= 1'b0;
        htype_q <= 2'bx;
      end else begin
        hsend_q <= hsend_q;
        htype_q <= htype_q;
      end
    end
  end


endmodule  // transaction
