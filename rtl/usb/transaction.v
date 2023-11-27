`timescale 1ns / 100ps
module transaction (
    clock,
    reset,

    // Configured device address (or all zero)
    usb_addr_i,

    // Decoded token from USB host
    tok_recv_i,
    tok_type_i,
    tok_addr_i,
    tok_endp_i,

    hsk_recv_i,  // Handshake from USB host
    hsk_type_i,
    hsk_send_o,  // Send handshake to USB host
    hsk_sent_i,
    hsk_type_o,

    // DATA0/1 info from the decoder, and to the encoder
    usb_recv_i,
    usb_type_i,
    usb_send_o,
    usb_sent_i,
    usb_type_o,

    // From USB packet decoder
    usb_tvalid_i,
    usb_tready_o,
    usb_tlast_i,
    usb_tdata_i,

    // To USB packet encoder
    trn_send_o,
    trn_type_o,
    trn_busy_i,
    trn_done_i,

    usb_tvalid_o,
    usb_tready_i,
    usb_tlast_o,
    usb_tdata_o,

    // Downstream chip-enables
    ep0_ce_o,
    ep1_ce_o,
    ep2_ce_o,

    // Control transfers
    ctl_start_o,
    ctl_rtype_o,
    ctl_rargs_o,
    ctl_value_o,
    ctl_index_o,
    ctl_length_o,

    ctl_tvalid_o,
    ctl_tready_i,
    ctl_tlast_o,
    ctl_tdata_o,

    ctl_tvalid_i,
    ctl_tready_o,
    ctl_tlast_i,
    ctl_tdata_i,

    // Bulk IN/OUT transfers
    blk_start_o,
    blk_dtype_o,
    blk_done1_i,
    blk_done2_i,
    blk_muxsel_o,

    blk_tvalid_o,
    blk_tready_i,
    blk_tlast_o,
    blk_tdata_o,

    blk_tvalid_i,
    blk_tready_o,
    blk_tlast_i,
    blk_tdata_i
);

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

  // Configured device address (or all zero)
  input [6:0] usb_addr_i;

  // Signals from the USB packet decoder (upstream)
  input tok_recv_i;
  input [1:0] tok_type_i;
  input [6:0] tok_addr_i;
  input [3:0] tok_endp_i;

  input hsk_recv_i;
  input [1:0] hsk_type_i;
  output hsk_send_o;
  input hsk_sent_i;
  output [1:0] hsk_type_o;

  // DATA0/1 info from the decoder, and to the encoder
  input usb_recv_i;
  input [1:0] usb_type_i;
  output usb_send_o;
  input usb_sent_i;
  output [1:0] usb_type_o;

  // USB control & bulk data received from host
  input usb_tvalid_i;
  output usb_tready_o;
  input usb_tlast_i;
  input [7:0] usb_tdata_i;

  // USB control & bulk data transmitted to the host
  output trn_send_o;
  output [1:0] trn_type_o;
  input trn_busy_i;
  input trn_done_i;

  output usb_tvalid_o;
  input usb_tready_i;
  output usb_tlast_o;
  output [7:0] usb_tdata_o;

  // Signals to the downstream endpoints
  // todo: make more generic ??
  output ep0_ce_o;  // Control EP
  output ep1_ce_o;  // Bulk EP #1
  output ep2_ce_o;  // Bulk EP #2

  // USB Control Transfer parameters and data-streams
  output ctl_start_o;
  output [7:0] ctl_rtype_o;  // todo:
  output [7:0] ctl_rargs_o;  // todo:
  output [15:0] ctl_value_o;
  output [15:0] ctl_index_o;
  output [15:0] ctl_length_o;

  output ctl_tvalid_o;
  input ctl_tready_i;
  output ctl_tlast_o;
  output [7:0] ctl_tdata_o;

  input ctl_tvalid_i;
  output ctl_tready_o;
  input ctl_tlast_i;
  input [7:0] ctl_tdata_i;

  // USB Bulk Transfer parameters and data-streams
  output blk_start_o;
  output blk_dtype_o;  // todo: OUT/IN, DATA0/1
  input blk_done1_i;  // todo: smrat ??
  input blk_done2_i;  // todo: smrat ??
  output blk_muxsel_o;  // todo: smrat ??

  output blk_tvalid_o;  // todo: not needed, as can use stream from the decoder !?
  input blk_tready_i;
  output blk_tlast_o;
  output [7:0] blk_tdata_o;

  input blk_tvalid_i;  // todo: not needed, as can use external MUX to encoder !?
  output blk_tready_o;
  input blk_tlast_i;
  input [7:0] blk_tdata_i;


  // -- Module Constants -- //

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam [1:0] DATA0 = 2'b00;
  localparam [1:0] DATA1 = 2'b10;

  localparam BLK_IDLE = 8'h00;
  localparam BLK_SETUP_DAT = 8'h02;

  localparam CTL_FAIL = 8'h00;
  localparam CTL_DONE = 8'h01;
  localparam CTL_SETUP_RX = 8'h02;
  localparam CTL_SETUP_ACK = 8'h03;

  localparam CTL_DATA_TOK = 8'hf0;
  localparam CTL_DATO_RX = 8'hf4;
  localparam CTL_DATO_ACK = 8'hf5;
  localparam CTL_DATI_TX = 8'hf8;
  localparam CTL_DATI_ACK = 8'hf9;

  localparam CTL_STATUS_TOK = 8'hcb;
  localparam CTL_STATUS_RX = 8'hcc;
  localparam CTL_STATUS_TX = 8'hcd;
  localparam CTL_STATUS_ACK = 8'hce;


  // -- Module State and Signals -- //

  reg ep0_ce_q, ep1_ce_q, ep2_ce_q;

  reg blk_start_q, ctl_start_q;
  reg blk_error_q, ctl_error_q;

  reg [7:0] ctl_rtype_q, ctl_rargs_q;
  reg [7:0] ctl_valhi_q, ctl_vallo_q;
  reg [7:0] ctl_idxhi_q, ctl_idxlo_q;
  reg [7:0] ctl_lenhi_q, ctl_lenlo_q;


  // -- Input and Output Signal Assignments -- //

  assign ep0_ce_o = ep0_ce_q;
  assign ep1_ce_o = ep1_ce_q;
  assign ep2_ce_o = ep2_ce_q;

  assign blk_start_o = blk_start_q;
  assign ctl_start_o = ctl_start_q;

  assign ctl_rtype_o = ctl_rtype_q;
  assign ctl_rargs_o = ctl_rargs_q;
  assign ctl_value_o = {ctl_valhi_q, ctl_vallo_q};
  assign ctl_index_o = {ctl_idxhi_q, ctl_idxlo_q};
  assign ctl_length_o = {ctl_lenhi_q, ctl_lenlo_q};

  assign usb_tready_o = 1'b1;  // todo: ...

  assign ctl_tready_o = 1'b1;


  // -- Downstream Chip-Enables -- //

  always @(posedge clock) begin
    if (reset) begin
      {ep2_ce_q, ep1_ce_q, ep0_ce_q} <= 3'b000;
    end else if (tok_recv_i && tok_addr_i == usb_addr_i) begin
      ep0_ce_q <= tok_type_i == 2'b11 && tok_endp_i == 4'h0;
      ep1_ce_q <= ENDPOINT1 != 0 && tok_endp_i == ENDPOINT1[3:0];
      ep2_ce_q <= ENDPOINT2 != 0 && tok_endp_i == ENDPOINT2[3:0];
    end else if (hsk_recv_i || hsk_sent_i) begin
      // todo: is this the correct condition to trigger off of?
      {ep2_ce_q, ep1_ce_q, ep0_ce_q} <= 3'b000;
    end
  end


  // -- Datapath to the USB Packet Encoder (for IN Transfers) -- //

  reg trn_zero_q; // zero-size data transfer ??
  reg trn_send_q;
  reg [1:0] trn_type_q;

  assign trn_send_o = trn_send_q;
  assign trn_type_o = trn_type_q;

  // todo: use an AXI4-Stream MUX
  assign usb_tvalid_o = trn_zero_q ? 1'b0 : ctl_tvalid_i;
  assign usb_tlast_o  = trn_zero_q ? 1'b1 : ctl_tlast_i;
  assign usb_tdata_o  = ctl_tdata_i;

  always @(posedge clock) begin
    if (reset) begin
      trn_zero_q <= 1'b0;
      trn_send_q <= 1'b0;
      trn_type_q <= 2'bxx;
    end else begin
      if (trn_busy_i) begin
        trn_zero_q <= 1'b0;
        trn_send_q <= 1'b0;
        trn_type_q <= 2'bxx;
      end else if (!trn_busy_i && state == ST_CTRL && xctrl == CTL_STATUS_TX && ctl_length_o == 0) begin
        trn_zero_q <= 1'b1;
        trn_send_q <= 1'b1;
        trn_type_q <= DATA1;
      end else begin
        trn_zero_q <= trn_zero_q;
        trn_send_q <= trn_send_q;
        trn_type_q <= trn_type_q;
      end
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
  localparam ST_BULK = 4'h1;  // USB Bulk IN/OUT Transfer
  localparam ST_CTRL = 4'h2;  // USB Control Transfer
  localparam ST_DUMP = 4'hf;  // ignoring xfer, or bad shit happened

  reg [3:0] state;
  reg [7:0] xbulk, xctrl;

  // todo: control the input MUX, and the output CE's
  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      ctl_req_type_q <= 3'b000;
    end else begin
      case (state)
        default: begin  // ST_IDLE
          //
          // Decode tokens until we see our address, and a valid endpoint
          ///
          if (tok_recv_i && tok_addr_i == usb_addr_i) begin
            if ((tok_type_i == TOK_IN || tok_type_i == TOK_OUT) &&
                (tok_endp_i == ENDPOINT1 || tok_endp_i == ENDPOINT2)) begin
              state <= ST_BULK;
              blk_start_q <= 1'b1;
            end else if (tok_type_i == TOK_SETUP && (tok_endp_i == 4'h0 ||  // PIPE0 required
                EP1_CONTROL && tok_endp_i == ENDPOINT1 ||
                          EP2_CONTROL && tok_endp_i == ENDPOINT2)) begin
              state <= ST_CTRL;
              blk_start_q <= 1'b0;
            end else begin
              // Either invalid endpoint, or unsupported transfer-type for the
              // requested endpoint.
              state <= ST_DUMP;
              blk_start_q <= 1'b0;
            end
          end else begin
            state <= ST_IDLE;
            blk_start_q <= 1'b0;
          end
        end

        ST_BULK: begin
          //
          // Wait for the USB to finish, and then return to IDLE
          ///
          if (blk_error_q) begin
            // Bulk Transfer has failed, wait for the USB to settle down
            state <= ST_DUMP;
          end else if (xbulk == BLK_IDLE) begin
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
          end else if (xctrl == CTL_DONE) begin
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
  reg blk_hsend_q;  // note: just a strobe (for the handshake FSM)
  reg [1:0] blk_htype_q;

  /*
  always @(posedge clock) begin
    if (state == ST_BULK) begin
      case (xbulk)
        default: begin
          xbulk   <= BLK_OUT_RX;
          hsend_q <= 1'b0;
          htype_q <= 2'bx;
        end
      endcase
    end else begin

      // Todo: too late to do anything ??
      if (blk_start_q) begin
        xbulk <= BLK_OUT_RX;
      end else begin
        xbulk <= BLK_IDLE;
      end
      blk_hsend_q <= 1'b0;
    end
  end
*/


  // -- Control Transfers FSM -- //

  //
  // These transfers have a predefined structure (see pp.225, USB 2.0 Spec), and
  // the initial 'DATA0' packet (after the 'SETUP' token) contains data laid-out
  // in the following format:
  //  - BYTE[0]   -- Request Type
  //  - BYTE[1]   -- Request
  //  - BYTE[3:2] -- Value
  //  - BYTE[5:4] -- Index
  //  - BYTE[7:6] -- Buffer length (can be zero)
  //  - BYTE[8..] -- Buffer contents (optional)
  // After receiving the packets: 'SETUP' & 'DATA0', a USB device must respond
  // with an 'ACK' handshake, before the "Data Stage" of the Control Transfer
  // begins.
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

  reg ctl_hsend_q;  // note: just a strobe (for the handshake FSM)
  reg [1:0] ctl_htype_q;

  reg [2:0] ctl_req_type_q;
  reg ctl_req_recv_q;
  reg ctl_tready_q;  // todo: pointless !?

  wire we_are_like_totally_done_with_data_w;
  reg odd_q;

  reg [2:0] xcptr;
  wire [2:0] xcnxt = xcptr + 1;

  // Parser of Control Transfer parameters
  // Todo:
  //  - conditional expr. does not exclude enough scenarios !?
  //  - "parse" the request-type for PIPE0 ??
  //  - figure out which 'xctrl[_]' bit to use for CE !?
  //  - if there is more data after the 8th byte, then forward that out (via
  //    an AXI4-Stream skid-register) !?
  always @(posedge clock) begin
    // if (reset || xctrl != CTL_SETUP_RX) begin
    if (state == ST_IDLE) begin
      xcptr <= 3'b000;
      ctl_start_q <= 1'b0;
    end else if (usb_tvalid_i && usb_tready_o) begin
      ctl_rtype_q <= xcptr == 3'b000 ? usb_tdata_i : ctl_rtype_q;
      ctl_rargs_q <= xcptr == 3'b001 ? usb_tdata_i : ctl_rargs_q;

      ctl_vallo_q <= xcptr == 3'b010 ? usb_tdata_i : ctl_vallo_q;
      ctl_valhi_q <= xcptr == 3'b011 ? usb_tdata_i : ctl_valhi_q;

      ctl_idxlo_q <= xcptr == 3'b100 ? usb_tdata_i : ctl_idxlo_q;
      ctl_idxhi_q <= xcptr == 3'b101 ? usb_tdata_i : ctl_idxhi_q;

      ctl_lenlo_q <= xcptr == 3'b110 ? usb_tdata_i : ctl_lenlo_q;
      ctl_lenhi_q <= xcptr == 3'b111 ? usb_tdata_i : ctl_lenhi_q;

      xcptr <= xcnxt;

      if (xcptr == 7) begin
        ctl_start_q <= 1'b1;
      end
    end else begin
      ctl_start_q <= 1'b0;
    end
  end

  // Control transfer handshakes
  always @(posedge clock) begin
    if (reset) begin
      ctl_hsend_q <= 1'b0;
      ctl_htype_q <= 2'bx;
    end else begin
      case (xctrl)
        CTL_SETUP_RX, CTL_DATO_RX, CTL_STATUS_RX: begin
          ctl_hsend_q <= usb_tvalid_i & usb_tready_o & usb_tlast_i;
          ctl_htype_q <= HSK_ACK;
        end
        default: begin
          ctl_hsend_q <= 1'b0;
          ctl_htype_q <= 2'bx;
        end
      endcase
    end
  end

  // todo: recognise control requests to PIPE0
  // todo: then extract the relevant fields
  always @(posedge clock) begin
    if (state == ST_CTRL) begin
      case (xctrl)
        CTL_FAIL: begin
          xctrl <= CTL_DONE;
        end

        //
        // Setup Stage
        ///
        default: begin  // CTL_SETUP_RX
          // todo: parsing and extract the initial bytes works ??
          if (usb_tvalid_i && usb_tready_o && usb_tlast_i) begin
            xctrl <= CTL_SETUP_ACK;
          end else begin
            xctrl <= CTL_SETUP_RX;
          end
        end

        CTL_SETUP_ACK: begin
          if (hsk_sent_i) begin
            xctrl <= ctl_length_o == 0 ? CTL_STATUS_TOK : CTL_DATA_TOK;
            odd_q <= 1'b1;  // Toggles after each DATA0/1
          end
        end

        //
        // Data Stage
        // Packets:
        //  {OUT/IN, DATA1, ACK}, {OUT/IN, DATA0, ACK}, ...
        ///
        CTL_DATA_TOK: begin
          // Wait for an IN/OUT token
          if (tok_recv_i) begin
            // todo: handle erroneous input ??
            xctrl <= tok_type_i == TOK_IN ? CTL_DATI_TX : CTL_DATO_RX;
          end
        end

        CTL_DATO_RX: begin  // Rx OUT from USB
          if (usb_tvalid_i && usb_tready_o && usb_tlast_i) begin
            xctrl <= CTL_DATO_ACK;
          end
        end

        CTL_DATO_ACK: begin
          if (we_are_like_totally_done_with_data_w) begin
            xctrl <= CTL_STATUS_TOK;
            odd_q <= 1'b1;
          end else if (hsk_sent_i) begin
            xctrl <= CTL_DATA_TOK;
            odd_q <= ~odd_q;
          end
        end

        CTL_DATI_TX: begin  // Tx IN to USB
          // todo: transition to 'CTL_STATUS' when 'length' bytes have been
          //   received
          // if (ctl_tvalid_i && ctl_tready_o && ctl_tlast_i) begin
          if (ctl_tvalid_o && ctl_tready_i && ctl_tlast_o) begin
            xctrl <= CTL_DATI_ACK;
          end
        end

        CTL_DATI_ACK: begin
          if (we_are_like_totally_done_with_data_w) begin
            xctrl <= CTL_STATUS_TOK;
            odd_q <= 1'b1;
          end else if (hsk_recv_i && hsk_type_i == HSK_ACK) begin
            xctrl <= CTL_DATA_TOK;
            odd_q <= ~odd_q;
          end
        end

        //
        // Status Stage
        // Packets: {IN/OUT, DATA1, ACK}
        ///
        CTL_STATUS_TOK: begin
          if (!odd_q) begin
            $error("%10t: INCORRECT DATA0/1 BIT");
          end

          if (tok_recv_i) begin
            xctrl <= tok_type_i == TOK_IN ? CTL_STATUS_TX : CTL_STATUS_RX;
          end
        end

        CTL_STATUS_RX: begin  // Rx Status from USB
          if (usb_tvalid_i && usb_tready_o && usb_tlast_i) begin
            xctrl <= CTL_STATUS_ACK;
          end
        end

        CTL_STATUS_TX: begin  // Tx Status to USB
          if (ctl_tvalid_i && ctl_tready_o && ctl_tlast_i) begin
            xctrl <= CTL_STATUS_ACK;
          end else if (trn_zero_q && trn_send_q) begin
            xctrl <= CTL_STATUS_ACK;
          end
        end

        CTL_STATUS_ACK: begin
          if (hsk_recv_i || hsk_sent_i) begin
            xctrl <= CTL_DONE;
            odd_q <= 1'b0;
          end
        end

        CTL_DONE: begin
          // Wait for the main FSM to return to IDLE, and then get ready for the
          // next Control Transfer.
          if (state == ST_IDLE) begin
            xctrl <= CTL_SETUP_RX;
          end
        end

      endcase
    end else begin
      // Just wait and Rx SETUP data
      xctrl <= CTL_SETUP_RX;
    end
  end


  // -- FSM to Issue Handshake Packets -- //

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



  // -- Simulation Only -- //

`ifdef __icarus

  reg [119:0] dbg_xctrl;

  always @* begin
    case (xctrl)
      CTL_FAIL: dbg_xctrl = "FAIL";
      CTL_DONE: dbg_xctrl = "DONE";
      CTL_SETUP_RX:  dbg_xctrl = "SETUP_RX";
      CTL_SETUP_ACK: dbg_xctrl = "SETUP_ACK";

      CTL_DATA_TOK: dbg_xctrl = "DATA_TOK";
      CTL_DATO_RX:  dbg_xctrl = "DATO_RX";
      CTL_DATO_ACK: dbg_xctrl = "DATO_ACK";
      CTL_DATI_TX:  dbg_xctrl = "DATI_TX";
      CTL_DATI_ACK: dbg_xctrl = "DATI_ACK";

      CTL_STATUS_TOK: dbg_xctrl = "STATUS_TOK";
      CTL_STATUS_RX: dbg_xctrl = "STATUS_RX";
      CTL_STATUS_TX: dbg_xctrl = "STATUS_TX";
      CTL_STATUS_ACK: dbg_xctrl = "STATUS_ACK";

      default:  dbg_xctrl = "UNKNOWN";
    endcase
  end

`endif


endmodule  // transaction
