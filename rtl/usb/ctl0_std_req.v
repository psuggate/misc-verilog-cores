`timescale 1ns / 100ps
/**
 * Handles USB CONTROL requests.
 * Todo:
 *  - read/write the status registers of other endpoints ??
 */
module ctl0_std_req #(
    parameter integer SERIAL_LENGTH = 8,
    parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001",

    parameter [15:0] VENDOR_ID = 16'hF4CE,
    parameter integer VENDOR_LENGTH = 19,
    parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago",

    parameter [15:0] PRODUCT_ID = 16'h0003,
    parameter integer PRODUCT_LENGTH = 8,
    parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB"
) (
    input clock,
    input reset,

    // Signals from the USB packet decoder (upstream)
    input tok_recv_i,
    input tok_ping_i,
    input [6:0] tok_addr_i,
    input [3:0] tok_endp_i,

    output enumerated_o,
    output configured_o,
    output [2:0] conf_num_o,
    output [6:0] address_o,
    output set_conf_o,
    output clr_conf_o,

    input  std_req_select_i,
    output std_req_done_o,
    input  std_req_timeout_i,

    // From the packet decoder
    input dec_tvalid_i,
    // output dec_tready_o,
    input dec_tkeep_i,
    input dec_tlast_i,
    input [3:0] dec_tuser_i,
    input [7:0] dec_tdata_i,

    input  hsk_recv_i,
    output hsk_send_o,
    input  hsk_sent_i,

    // DATA0/1 info from the decoder, and to the encoder
    input eop_recv_i,
    input usb_recv_i,
    input usb_busy_i,
    input usb_sent_i,

    // To the packet encoder
    output enc_tvalid_o,
    input enc_tready_i,
    output enc_tkeep_o,
    output enc_tlast_o,
    output [3:0] enc_tuser_o,
    output [7:0] enc_tdata_o
);


  // -- Module State and Signals -- //

  reg ctl_start_q, ctl_cycle_q, ctl_error_q;

  reg [7:0] ctl_rtype_q, ctl_rargs_q;
  reg [7:0] ctl_valhi_q, ctl_vallo_q;
  reg [7:0] ctl_idxhi_q, ctl_idxlo_q;
  reg [7:0] ctl_lenhi_q, ctl_lenlo_q;

  // FSM states for control transfers
  localparam CTL_DONE = 4'h0;
  localparam CTL_SETUP_RX = 4'h1;
  localparam CTL_SETUP_ACK = 4'h2;

  localparam CTL_DATO_RX = 4'h3;
  localparam CTL_DATO_ACK = 4'h4;
  localparam CTL_DATO_TOK = 4'h5;

  localparam CTL_DATI_TX = 4'h6;
  localparam CTL_DATI_ACK = 4'h7;
  localparam CTL_DATI_TOK = 4'h8;

  localparam CTL_STATUS_RX = 4'h9;
  localparam CTL_STATUS_TX = 4'ha;
  localparam CTL_STATUS_ACK = 4'hb;

  reg [3:0] xctrl;


  //
  //  Control Transfer "Standard Request" FSM
  ///
  wire ctl_set_done_w = ~ctl_rtype_q[7] & ctl_event_i;
  wire ctl_get_done_w = ctl_rtype_q[7] & ctl_tvalid_i & ctl_tready_o & ctl_tlast_i;
  wire ctl_done_w = ctl_cycle_q & (ctl_set_done_w | ctl_get_done_w);
  wire [3:0] ctl_endpt_w;

  wire ctl0_start_w, ctl0_cycle_w, ctl0_error_w, ctl0_event_w;
  wire ctl0_tvalid_w, ctl0_tready_w, ctl0_tlast_w;
  wire [7:0] ctl0_tdata_w;


  // -- DATA0/1/2/M Logic -- //

  reg set_parity, clr_parity, parity_q;
  wire ctrl_ack_w = hsk_recv_i && dec_tuser_i[3:2] == HSK_ACK &&
       (xctrl == CTL_DATI_ACK || xctrl == CTL_STATUS_ACK);

  always @* begin
    //
    //  Configuration endpoint DATA0/1 parity logic
    ///
    set_parity = 1'b0;
    clr_parity = 1'b0;

    if (tok_endp_i == 0) begin
      if (tok_recv_i) begin
        if (usb_tuser_i == {TOK_SETUP, 2'b01}) begin
          set_parity = 1'b0;
          clr_parity = 1'b1;
        end else if (usb_tuser_i[3:2] == TOK_OUT && xctrl == CTL_DATI_TOK ||
                     usb_tuser_i[3:2] == TOK_IN  && xctrl == CTL_DATO_TOK
                     ) begin
          set_parity = 1'b1;
          clr_parity = 1'b0;
        end
      end else if (usb_recv_i) begin
        case (xctrl)
          CTL_DATO_RX: begin
            set_parity = ~parity_q;
            clr_parity = parity_q;
          end
          CTL_SETUP_RX: begin
            set_parity = 1'b1;
            clr_parity = 1'b0;
          end
          CTL_STATUS_RX: begin
            set_parity = 1'b0;
            clr_parity = 1'b1;
          end
          default: begin
            set_parity = 1'b0;
            clr_parity = 1'b0;
          end
        endcase
      end else if (ctrl_ack_w || ctl0_event_w) begin
        set_parity = ~parity_q;
        clr_parity = parity_q;
      end
    end
  end

  // Parity-state J/K flip-flops //
  always @(posedge clock) begin
    // Configuration endpoint DATAx parity-bit
    if (reset || clr_parity) begin
      parity_q <= 1'b0;
    end else if (set_parity) begin
      parity_q <= 1'b1;
    end
  end


  // -- Compute the USB Tx Packet PID -- //

  always @(posedge clock) begin
    if (reset) begin
      tuser_q <= 4'd0;
    end else if (!hsend_q && eop_recv_i) begin
      tuser_q <= {HSK_ACK, 2'b10};
    end else if (xctrl == CTL_DATO_TOK && tok_recv_i && usb_tuser_i[3:2] == TOK_IN) begin
      tuser_q <= {DATA1, 2'b11};
    end else if (xctrl == CTL_DATI_TX && ctl_tvalid_i) begin
      tuser_q <= {parityx_w ? DATA1 : DATA0, 2'b11};
    end else if (xbulk == BLK_IDLE && tok_recv_i && usb_tuser_i[3:2] == TOK_IN) begin
      tuser_q <= {parityx_w ? DATA1 : DATA0, 2'b11};
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
    if (!std_req_select_i) begin
      xcptr <= 3'b000;
      ctl_lenlo_q <= 0;
      ctl_lenhi_q <= 0;
      ctl_start_q <= 1'b0;
      ctl_cycle_q <= 1'b0;
    end else if (xctrl == CTL_SETUP_RX && dec_tvalid_i && dec_tkeep_i && dec_tready_o) begin
      ctl_rtype_q <= xcptr == 3'b000 ? dec_tdata_i : ctl_rtype_q;
      ctl_rargs_q <= xcptr == 3'b001 ? dec_tdata_i : ctl_rargs_q;

      ctl_vallo_q <= xcptr == 3'b010 ? dec_tdata_i : ctl_vallo_q;
      ctl_valhi_q <= xcptr == 3'b011 ? dec_tdata_i : ctl_valhi_q;

      ctl_idxlo_q <= xcptr == 3'b100 ? dec_tdata_i : ctl_idxlo_q;
      ctl_idxhi_q <= xcptr == 3'b101 ? dec_tdata_i : ctl_idxhi_q;

      ctl_lenlo_q <= xcptr == 3'b110 ? dec_tdata_i : ctl_lenlo_q;
      ctl_lenhi_q <= xcptr == 3'b111 ? dec_tdata_i : ctl_lenhi_q;

      if (xcptr == 7) begin
        ctl_start_q <= 1'b1;
        ctl_cycle_q <= 1'b1;
      end else begin
        xcptr <= xcnxt;
      end
    end else begin
      ctl_start_q <= 1'b0;
      ctl_cycle_q <= ctl_done_w ? 1'b0 : ctl_cycle_q;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      ctl_error_q <= 1'b0;
    end else if (ctl_cycle_q && ctl_error_i) begin
      ctl_error_q <= 1'b1;
    end
  end

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
    if (!std_req_select_i) begin
      // Just wait and Rx SETUP data
      xctrl <= CTL_SETUP_RX;
    end else begin
      case (xctrl)
        //
        // Setup Stage
        ///
        default: begin  // CTL_SETUP_RX
          if (eop_recv_i) begin
            xctrl <= CTL_SETUP_ACK;
          end else begin
            xctrl <= CTL_SETUP_RX;
          end
        end

        CTL_SETUP_ACK: begin
          if (hsk_sent_i) begin
            xctrl <= ctl_length_o == 0 ? CTL_DATO_TOK : 
                     ctl_rtype_q[7] ? CTL_DATI_TOK : CTL_DATO_TOK;
          end
        end

        //
        // Data Stage
        // Packets:
        //  {OUT/IN, DATA1, ACK}, {OUT/IN, DATA0, ACK}, ...
        ///
        // Data OUT //
        CTL_DATO_RX: begin  // Rx OUT from USB Host
          // todo:
          //  - to be compliant, we have to check bytes-sent !?
          //  - catch Rx errors (indicated by the PHY) !?
          if (eop_recv_i) begin
            xctrl <= CTL_DATO_ACK;
          end
        end

        CTL_DATO_ACK: begin
          if (hsk_sent_i) begin
            xctrl <= CTL_DATO_TOK;
          end
        end

        CTL_DATO_TOK: begin
          // Wait for the next token, and an 'OUT' means that we receive more
          // from the host, and 'IN' means that we are now in the 'STATUS'
          // stage.
          // todo:
          //  - to be compliant, we have to check bytes-received !?
          if (tok_recv_i) begin
            xctrl <= dec_tuser_i[3:2] == TOK_OUT ? CTL_DATO_RX : CTL_STATUS_TX;
          end else if (hsk_recv_i || usb_recv_i) begin
`ifdef __icarus
            $error("%10t: Unexpected (T=%1d D=%1d)", $time, tok_recv_i, usb_recv_i);
`endif
            xctrl <= CTL_DONE;
          end
        end

        // Data IN //
        CTL_DATI_TX: begin  // Tx IN to USB Host
          if (usb_sent_i) begin
            xctrl <= CTL_DATI_ACK;
          end
        end

        CTL_DATI_ACK: begin
          if (hsk_recv_i) begin
            xctrl <= dec_tuser_i[3:2] == HSK_ACK ? CTL_DATI_TOK : CTL_DONE;
          end else if (tok_recv_i || usb_recv_i) begin  // Non-ACK
`ifdef __icarus
            $error("%10t: Unexpected (T=%1d D=%1d)", $time, tok_recv_i, usb_recv_i);
`endif
            xctrl <= CTL_DONE;
          end
        end

        CTL_DATI_TOK: begin
          // Wait for the next token, and an 'IN' means that we send more to the
          // host, and 'OUT' means that we are now in the 'STATUS' stage.
          // todo:
          //  - to be compliant, we have to check bytes-received !?
          if (tok_recv_i) begin
            xctrl <= dec_tuser_i[3:2] == TOK_IN ? CTL_DATI_TX : CTL_STATUS_RX;
          end else if (hsk_recv_i || usb_recv_i) begin
`ifdef __icarus
            $error("%10t: Unexpected (T=%1d D=%1d)", $time, tok_recv_i, usb_recv_i);
            #100 $fatal;
`endif
            xctrl <= CTL_DONE;
          end
        end

        //
        // Status Stage
        // Packets: {IN/OUT, DATA1, ACK}
        ///
        CTL_STATUS_RX: begin  // Rx Status from USB
          if (!parity_q) begin
            $error("%10t: INCORRECT DATA0/1 BIT", $time);
          end

          if (dec_tvalid_i && dec_tready_o && dec_tlast_i) begin
            xctrl <= CTL_STATUS_ACK;
          end else if (usb_zero_w && dec_tuser_i[3:2] == DATA1) begin
            // We have received a zero-data 'Status' packet
            xctrl <= CTL_STATUS_ACK;
          end
        end

        CTL_STATUS_TX: begin  // Tx Status to USB
          if (usb_sent_i) begin
            xctrl <= CTL_STATUS_ACK;
          end
        end

        CTL_STATUS_ACK: begin
          // Todo: can just chill here indefinitely, because we do not need the
          //   `CTL_DONE` state, nor is there anything to do even if we do not
          //   get the appropriate response (and the timeout will be handled
          //   elsewhere) !?
          // Perhaps "ctl_done_q <= hsk_recv_i || hsk_sent_i;" ??
          if (hsk_recv_i || hsk_sent_i) begin
            xctrl <= CTL_DONE;
          end
        end

        CTL_DONE: begin
          // Wait for the main FSM to return to IDLE, and then get ready for the
          // next Control Transfer.
          if (state != ST_CTRL) begin
            xctrl <= CTL_SETUP_RX;
          end
        end

      endcase
    end
  end


  // -- USB Default (PIPE0) Configuration Endpoint -- //

  ctl_pipe0 #(
      // Device string descriptors [Optional]
      .MANUFACTURER_LEN(VENDOR_LENGTH),
      .MANUFACTURER(VENDOR_STRING),
      .PRODUCT_LEN(PRODUCT_LENGTH),
      .PRODUCT(PRODUCT_STRING),
      .SERIAL_LEN(SERIAL_LENGTH),
      .SERIAL(SERIAL_STRING),

      // Configuration for the device endpoints
      .CONFIG_DESC_LEN(CONF_DESC_SIZE),
      .CONFIG_DESC(CONF_DESC_VALS),

      // Product info
      .VENDOR_ID (VENDOR_ID),
      .PRODUCT_ID(PRODUCT_ID)
  ) U_CFG_PIPE0 (
      .clock(clock),
      .reset(reset),

      .start_i (ctl0_start_w),
      .select_i(ctl0_cycle_w),
      .error_o (ctl0_error_w),
      .event_o (ctl0_event_w),

      .configured_o(configured_o),
      .usb_conf_o  (conf_num_o),
      .usb_enum_o  (enumerated_o),
      .usb_addr_o  (address_o),

      .req_endpt_i (ctl_endpt_w),
      .req_type_i  (ctl_rtype_q),
      .req_args_i  (ctl_rargs_q),
      .req_value_i ({ctl_valhi_q, ctl_vallo_q}),
      .req_index_i ({ctl_idxhi_q, ctl_idxlo_q}),
      .req_length_i({ctl_lenhi_q, ctl_lenlo_q}),

      // AXI4-Stream for device descriptors
      .m_tvalid_o(ctl0_tvalid_w),
      .m_tlast_o (ctl0_tlast_w),
      .m_tdata_o (ctl0_tdata_w),
      .m_tready_i(ctl0_tready_w)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  always @* begin
    case (xctrl)
      CTL_DONE: dbg_xctrl = "DONE";
      CTL_SETUP_RX: dbg_xctrl = "SETUP_RX";
      CTL_SETUP_ACK: dbg_xctrl = "SETUP_ACK";

      CTL_DATO_RX:  dbg_xctrl = "DATO_RX";
      CTL_DATO_ACK: dbg_xctrl = "DATO_ACK";
      CTL_DATO_TOK: dbg_xctrl = "DATO_TOK";

      CTL_DATI_TX:  dbg_xctrl = "DATI_TX";
      CTL_DATI_ACK: dbg_xctrl = "DATI_ACK";
      CTL_DATI_TOK: dbg_xctrl = "DATI_TOK";

      CTL_STATUS_RX:  dbg_xctrl = "STATUS_RX";
      CTL_STATUS_TX:  dbg_xctrl = "STATUS_TX";
      CTL_STATUS_ACK: dbg_xctrl = "STATUS_ACK";

      default: dbg_xctrl = "UNKNOWN";
    endcase
  end

`endif  /* __icarus */


endmodule  // ctl0_std_req
