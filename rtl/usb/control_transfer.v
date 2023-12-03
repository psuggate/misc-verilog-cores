`timescale 1ns / 100ps
module control_transfer
 (
  input clock,
  input reset,

  // Configured device address (or all zero)
  input [6:0] usb_addr_i,

  // input fsm_ctrl_i,
  // input fsm_idle_i,
  output ctl_done_o,

  // USB Control Transfer parameters and data-streams
  output ctl_start_o,
  output ctl_cycle_o,
  input ctl_error_i,
  output [7:0] ctl_rtype_o,  // todo:
  output [7:0] ctl_rargs_o,  // todo:
  output [15:0] ctl_value_o,
  output [15:0] ctl_index_o,
  output [15:0] ctl_length_o,

  output ctl_tvalid_o,
  input ctl_tready_i,
  output ctl_tlast_o,
  output [7:0] ctl_tdata_o,

  input ctl_tvalid_i,
  output ctl_tready_o,
  input ctl_tlast_i,
  input [7:0] ctl_tdata_i,

  // Signals from the USB packet decoder (upstream)
  input tok_recv_i,
  input [1:0] tok_type_i,
  input [6:0] tok_addr_i,
  input [3:0] tok_endp_i,

  input hsk_recv_i,
  input [1:0] hsk_type_i,
  output hsk_send_o,
  input hsk_sent_i,
  output [1:0] hsk_type_o,

  // DATA0/1 info from the decoder, and to the encoder
  input usb_recv_i,
  input [1:0] usb_type_i,
  output usb_send_o,
  input  usb_busy_i,
  input usb_sent_i,
  output [1:0] usb_type_o,

  // USB control & bulk data received from host
  input usb_tvalid_i,
  output usb_tready_o,
  input usb_tlast_i,
  input [7:0] usb_tdata_i,

  output usb_tvalid_o,
  input usb_tready_i,
  output usb_tlast_o,
  output [7:0] usb_tdata_o
 );


  // -- Module Constants -- //

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam [1:0] DATA0 = 2'b00;
  localparam [1:0] DATA1 = 2'b10;

  // FSM states
  localparam CTL_DONE = 4'h0;
  localparam CTL_SETUP_RX = 4'h1;
  localparam CTL_SETUP_ACK = 4'h2;

  localparam CTL_DATA_TOK = 4'h3;
  localparam CTL_DATO_RX = 4'h4;
  localparam CTL_DATO_ACK = 4'h5;
  localparam CTL_DATI_TX = 4'h6;
  localparam CTL_DATI_ACK = 4'h7;

  localparam CTL_STATUS_TOK = 4'h8;
  localparam CTL_STATUS_RX = 4'h9;
  localparam CTL_STATUS_TX = 4'ha;
  localparam CTL_STATUS_ACK = 4'hb;


  // -- Module State and Signals -- //

  reg ctl_start_q, ctl_cycle_q, ctl_error_q;

  reg [7:0] ctl_rtype_q, ctl_rargs_q;
  reg [7:0] ctl_valhi_q, ctl_vallo_q;
  reg [7:0] ctl_idxhi_q, ctl_idxlo_q;
  reg [7:0] ctl_lenhi_q, ctl_lenlo_q;

  reg odd_q;
  reg [2:0] xcptr;
  wire [2:0] xcnxt = xcptr + 1;
  reg [3:0] xctrl; //  = CTL_SETUP_RX;

  reg [9:0] tx_count;
  wire [9:0] tx_cnext = tx_count + 10'd1;


  // -- Input and Output Signal Assignments -- //

  assign ctl_done_o = xctrl == CTL_DONE;

  assign ctl_cycle_o = ctl_cycle_q;
  assign ctl_start_o = ctl_start_q;

  assign ctl_rtype_o = ctl_rtype_q;
  assign ctl_rargs_o = ctl_rargs_q;
  assign ctl_value_o = {ctl_valhi_q, ctl_vallo_q};
  assign ctl_index_o = {ctl_idxhi_q, ctl_idxlo_q};
  assign ctl_length_o = {ctl_lenhi_q, ctl_lenlo_q};

  assign ctl_tvalid_o = 1'b0; // usb_tready_i;
  assign usb_tready_o = 1'b1;  // todo: ...
  assign ctl_tlast_o  = 1'b0;
  assign ctl_tdata_o  = 8'h00;

  assign usb_tvalid_o = ctl_tvalid_i;
  assign ctl_tready_o = usb_tready_i;
  assign usb_tlast_o  = ctl_tlast_i;
  assign usb_tdata_o  = ctl_tdata_i;


  // -- Datapath from the USB Packet Decoder -- //

  reg  usb_recv_q;
  wire usb_zero_w;

  // Zero-size data transfers (typically for STATUS messages)
  assign usb_zero_w = usb_recv_q && !usb_tvalid_i && usb_tlast_i;

  // Delay the 'RECV' signal to align with 'tlast' (and '!tvalid'), as this
  // condition indicates that the received packet contains no data.
  always @(posedge clock) begin
    if (reset) begin
      usb_recv_q <= 1'b0;
    end else if (usb_recv_i) begin
      usb_recv_q <= 1'b1;
    end else if (usb_tvalid_i || usb_tlast_i) begin
      usb_recv_q <= 1'b0;
    end
  end


  // -- FSM to Issue Handshake Packets -- //

  reg hsend_q;
  reg [1:0] htype_q;

  assign hsk_send_o = hsend_q;
  assign hsk_type_o = htype_q;

  // Control transfer handshakes
  always @(posedge clock) begin
    if (reset) begin
      hsend_q <= 1'b0;
      htype_q <= 2'bx;
    end else if (!hsend_q && state != ST_IDLE) begin
      case (xctrl)
        CTL_SETUP_RX, CTL_DATO_RX, CTL_STATUS_RX: begin
          hsend_q <= usb_tvalid_i && usb_tready_o && usb_tlast_i ||
                     usb_zero_w && usb_type_i == DATA1;
          htype_q <= HSK_ACK;
        end
        default: begin
          hsend_q <= 1'b0;
          htype_q <= 2'bx;
        end
      endcase
    end else if (hsk_sent_i) begin
      hsend_q <= 1'b0;
      htype_q <= 2'bx;
    end else begin
      hsend_q <= hsend_q;
      htype_q <= htype_q;
    end
  end


  // -- Datapath to the USB Packet Encoder (for IN Transfers) -- //

  assign usb_send_o = trn_send_q;
  assign usb_type_o = trn_type_q;


  reg trn_zero_q;  // zero-size data transfer ??
  reg trn_send_q;
  reg [1:0] trn_type_q;

  assign usb_send_o   = trn_send_q;
  assign usb_type_o   = trn_type_q;

  always @(posedge clock) begin
    if (reset || usb_busy_i) begin
      trn_zero_q <= 1'b0;
      trn_send_q <= 1'b0;
      trn_type_q <= 2'bxx;
    end else if (state == ST_CTRL) begin
      if (xctrl == CTL_STATUS_TX && ctl_length_o == 0) begin
        trn_zero_q <= 1'b1;
        trn_send_q <= 1'b1;
        trn_type_q <= DATA1;
      end else if ((xctrl == CTL_DATI_TX || xctrl == CTL_STATUS_TX) && ctl_tvalid_i) begin
        trn_zero_q <= 1'b0;
        trn_send_q <= 1'b1;
        trn_type_q <= odd_q ? DATA1 : DATA0;  // todo: odd/even
      end else begin
        trn_zero_q <= trn_zero_q;
        trn_send_q <= trn_send_q;
        trn_type_q <= trn_type_q;
      end
    end else begin
      trn_zero_q <= trn_zero_q;
      trn_send_q <= trn_send_q;
      trn_type_q <= trn_type_q;
    end
  end


  // -- Transaction FSM -- //

  //
  // Hierarchical, pipelined FSM that just enables the relevant lower-level FSM,
  // waits for it to finish, or handles any errors.
  //
  // Todo: should this FSM handle no-data responses ??
  //
  localparam ST_IDLE = 3'h1;
  localparam ST_CTRL = 3'h2;  // USB Control Transfer
  localparam ST_DUMP = 3'h4;  // ignoring xfer, or bad shit happened

  localparam ER_NONE = 3'h0;
  localparam ER_BLKI = 3'h1;
  localparam ER_BLKO = 3'h2;
  localparam ER_TOKN = 3'h3;
  localparam ER_ADDR = 3'h4;
  localparam ER_ENDP = 3'h5;
  localparam ER_CONF = 3'h6;

  reg [2:0] state;
  reg err_start_q = 1'b0;
  reg [2:0] err_code_q = ER_NONE;

  // todo: control the input MUX, and the output CE's
  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
      err_start_q <= 1'b0;
      err_code_q <= ER_NONE;
    end else begin
      case (state)
        default: begin  // ST_IDLE
          //
          // Decode tokens until we see our address, and a valid endpoint
          ///
          if (tok_recv_i && tok_addr_i == usb_addr_i) begin
            if (tok_type_i == TOK_IN || tok_type_i == TOK_OUT) begin
              state <= ST_DUMP;
              err_start_q <= 1'b1;
              err_code_q <= tok_type_i == TOK_IN ? ER_BLKI : ER_BLKO;
            end else if (tok_type_i == TOK_SETUP) begin
              state <= ST_CTRL;
              err_start_q <= tok_endp_i != 4'h0;
              err_code_q <= tok_endp_i != 4'h0 ? ER_ENDP : ER_NONE;
            end else begin
              // Either invalid endpoint, or unsupported transfer-type for the
              // requested endpoint.
              state <= ST_DUMP;
              err_start_q <= 1'b1;
              err_code_q <= ER_TOKN;
            end
          end else begin
            state <= ST_IDLE;
            err_start_q <= 1'b0;
          end
        end

        ST_CTRL: begin
          //
          // Wait for the USB to finish, and then return to IDLE
          ///
          if (ctl_error_q) begin
            // Control Transfer has failed, wait for the USB to settle down
            state <= ST_DUMP;
            err_start_q <= 1'b1;
            err_code_q <= ER_CONF;
          end else if (xctrl == CTL_DONE) begin
            state <= ST_IDLE;
          end
        end

        ST_DUMP: begin
          //
          // todo: Wait for the USB to finish, and then return to IDLE
          ///
          state <= ST_DUMP;
          err_start_q <= 1'b1;
        end
      endcase
    end
  end


  // -- Parser for Control Transfer Parameters -- //

  // Todo:
  //  - conditional expr. does not exclude enough scenarios !?
  //  - "parse" the request-type for PIPE0 ??
  //  - figure out which 'xctrl[_]' bit to use for CE !?
  //  - if there is more data after the 8th byte, then forward that out (via
  //    an AXI4-Stream skid-register) !?
  always @(posedge clock) begin
    if (reset || state == ST_IDLE) begin
      xcptr <= 3'b000;
      ctl_lenlo_q <= 0;
      ctl_lenhi_q <= 0;
      ctl_start_q <= 1'b0;
      ctl_cycle_q <= 1'b0;
    end else if (xctrl == CTL_SETUP_RX && usb_tvalid_i && usb_tready_o) begin
      ctl_rtype_q <= xcptr == 3'b000 ? usb_tdata_i : ctl_rtype_q;
      ctl_rargs_q <= xcptr == 3'b001 ? usb_tdata_i : ctl_rargs_q;

      ctl_vallo_q <= xcptr == 3'b010 ? usb_tdata_i : ctl_vallo_q;
      ctl_valhi_q <= xcptr == 3'b011 ? usb_tdata_i : ctl_valhi_q;

      ctl_idxlo_q <= xcptr == 3'b100 ? usb_tdata_i : ctl_idxlo_q;
      ctl_idxhi_q <= xcptr == 3'b101 ? usb_tdata_i : ctl_idxhi_q;

      ctl_lenlo_q <= xcptr == 3'b110 ? usb_tdata_i : ctl_lenlo_q;
      ctl_lenhi_q <= xcptr == 3'b111 ? usb_tdata_i : ctl_lenhi_q;

      if (xcptr == 7) begin
        ctl_start_q <= 1'b1;
        ctl_cycle_q <= 1'b1;
      end else begin
        xcptr <= xcnxt;
      end
    end else begin
      ctl_start_q <= 1'b0;
      if (ctl_tvalid_i && ctl_tready_o && ctl_tlast_i) begin
        ctl_cycle_q <= 1'b0;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      ctl_error_q <= 1'b0;
    end else if (ctl_cycle_q && ctl_error_i) begin
      ctl_error_q <= 1'b1;
    end
  end


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

  always @(posedge clock) begin
    if (reset) begin
      tx_count <= 0;
    end else begin
      if (xctrl == CTL_DATI_TX && usb_tvalid_o && usb_tready_i) begin
        tx_count <= tx_cnext;
      end else if (xctrl == CTL_DONE || xctrl == CTL_SETUP_RX) begin
        tx_count <= 0;
      end
    end
  end
  

  // todo: recognise control requests to PIPE0
  // todo: then extract the relevant fields
  always @(posedge clock) begin
    // if (fsm_ctrl_i) begin
    if (state == ST_CTRL) begin
      case (xctrl)
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

        CTL_DATO_RX: begin  // Rx OUT from USB Host
          if (usb_tvalid_i && usb_tready_o && usb_tlast_i) begin
            xctrl <= CTL_DATO_ACK;
          end
        end

        CTL_DATO_ACK: begin
          if (hsk_recv_i && hsk_type_i == HSK_ACK) begin
            xctrl <= CTL_STATUS_TOK;
            odd_q <= 1'b1;
          end else if (hsk_sent_i) begin
            xctrl <= CTL_DATA_TOK;
            odd_q <= ~odd_q;
          end
        end

        CTL_DATI_TX: begin  // Tx IN to USB Host
          if (ctl_tvalid_i && ctl_tready_o && ctl_tlast_i) begin
            xctrl <= CTL_DATI_ACK;
          // end else if (tx_cnext == ctl_length_o[9:0]) begin
          //   xctrl <= CTL_DATI_ACK;
          end
        end

        CTL_DATI_ACK: begin
          if (hsk_recv_i && hsk_type_i == HSK_ACK) begin
            xctrl <= CTL_STATUS_TOK;
            odd_q <= 1'b1;

            /**
             * TODO: can not support this until data-path CTL -> ENC is sorted-
             *   out, because (AXI-S, skid) pipepline-registers break the phase
             *   of 'ctl_done_i'.
             */
            /*
            if (ctl_done_i) begin
              xctrl <= CTL_STATUS_TOK;
              odd_q <= 1'b1;
            end else begin
              xctrl <= CTL_DATA_TOK;
              odd_q <= ~odd_q;
            end
            */
          end else if (hsk_recv_i || tok_recv_i) begin // Non-ACK
            xctrl <= CTL_DONE;
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
          end else if (usb_zero_w && usb_type_i == DATA1) begin
            // We have received a zero-data 'Status' packet
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
          // if (fsm_idle_i) begin
            xctrl <= CTL_SETUP_RX;
          end
        end

      endcase
    end else begin
      // Just wait and Rx SETUP data
      xctrl <= CTL_SETUP_RX;
    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_CTRL: dbg_state = "CTRL";
      ST_DUMP: dbg_state = "DUMP";
      default: dbg_state = "XXXX";
    endcase
  end

  reg [119:0] dbg_xctrl;

  always @* begin
    case (xctrl)
      CTL_DONE: dbg_xctrl = "DONE";
      CTL_SETUP_RX: dbg_xctrl = "SETUP_RX";
      CTL_SETUP_ACK: dbg_xctrl = "SETUP_ACK";

      CTL_DATA_TOK: dbg_xctrl = "DATA_TOK";
      CTL_DATO_RX:  dbg_xctrl = "DATO_RX";
      CTL_DATO_ACK: dbg_xctrl = "DATO_ACK";
      CTL_DATI_TX:  dbg_xctrl = "DATI_TX";
      CTL_DATI_ACK: dbg_xctrl = "DATI_ACK";

      CTL_STATUS_TOK: dbg_xctrl = "STATUS_TOK";
      CTL_STATUS_RX:  dbg_xctrl = "STATUS_RX";
      CTL_STATUS_TX:  dbg_xctrl = "STATUS_TX";
      CTL_STATUS_ACK: dbg_xctrl = "STATUS_ACK";

      default: dbg_xctrl = "UNKNOWN";
    endcase
  end

`endif


endmodule // control_transfer
