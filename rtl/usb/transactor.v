`timescale 1ns / 100ps
//
//  TODO:
//   - this design is bad!
//   - just write a 'bulk_transfer' module, and add it to the 'control_transfer' 
//     module !?
//
module transactor
#(
  parameter ENDPOINT1 = 1,
  parameter ENDPOINT2 = 2
) (
  input clock,
  input reset,

  // Configured device address (or all zero)
  input [6:0] usb_addr_i,

  output fsm_idle_o,
  output fsm_bulk_o,
  input blk_done_i,
  output fsm_ctrl_o,
  input ctl_done_i,
  output fsm_dump_o,

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
  output [7:0] usb_tdata_o,

  // USB Control Transfer parameters and data-streams
  output ctl_start_o,
  output ctl_cycle_o,
  input ctl_error_i,

  output ctl_hsk_recv_o,
  input [1:0] ctl_hsk_type_i,
  input ctl_hsk_send_i,
  output ctl_hsk_sent_o,
  output [1:0] ctl_hsk_type_o,

  output ctl_dat_recv_o,
  input [1:0] ctl_dat_type_i,
  input ctl_dat_send_i,
  output ctl_dat_busy_o,
  output ctl_dat_sent_o,
  output [1:0] ctl_dat_type_o,

  output ctl_tvalid_o,
  input ctl_tready_i,
  output ctl_tlast_o,
  output [7:0] ctl_tdata_o,

  input ctl_tvalid_i,
  output ctl_tready_o,
  input ctl_tlast_i,
  input [7:0] ctl_tdata_i,

    // Bulk IN/OUT transfers
  output blk_hsk_recv_o,
  input [1:0] blk_hsk_type_i,
  input blk_hsk_send_i,
  output blk_hsk_sent_o,
  output [1:0] blk_hsk_type_o,

  output blk_dat_recv_o,
  input [1:0] blk_dat_type_i,
  input blk_dat_send_i,
  output blk_dat_sent_o,
  output [1:0] blk_dat_type_o,

    output blk_start_o,
    output blk_cycle_o,
    output [1:0] blk_dtype_o,
    output blk_muxsel_o,
   input blk_error_i,

  output blk_tvalid_o,
  input blk_tready_i,
  output blk_tlast_o,
  output [7:0] blk_tdata_o,

  input blk_tvalid_i,
  output blk_tready_o,
  input blk_tlast_i,
  input [7:0] blk_tdata_i
 );


  // -- Constants -- //

  localparam NO_BULK_EP = 1;

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam [1:0] DATA0 = 2'b00;
  localparam [1:0] DATA1 = 2'b10;

  // Transaction top-level states
  localparam [3:0] ST_IDLE = 4'h1;
  localparam [3:0] ST_BULK = 4'h2;  // USB Bulk Transfer
  localparam [3:0] ST_CTRL = 4'h4;  // USB Control Transfer
  localparam [3:0] ST_DUMP = 4'h8;  // ignoring xfer, or bad shit happened

  // Error-codes
  localparam ER_NONE = 3'h0;
  localparam ER_BLKI = 3'h1;
  localparam ER_BLKO = 3'h2;
  localparam ER_TOKN = 3'h3;
  localparam ER_ADDR = 3'h4;
  localparam ER_ENDP = 3'h5;
  localparam ER_CONF = 3'h6;


  // -- State & Signals -- //

  reg [2:0] state;
  reg err_start_q = 1'b0;
  reg [2:0] err_code_q = ER_NONE;

  reg ctl_start_q, ctl_cycle_q, ctl_error_q;


  // -- Output Assignments -- //

  assign fsm_idle_o = state == ST_IDLE;
  assign fsm_bulk_o = state == ST_BULK;
  assign fsm_ctrl_o = state == ST_CTRL;
  assign fsm_dump_o = state == ST_DUMP;


  //
  // If support for multiple endpoints is enabled, then we have to (de-)MUX USB
  // transfers.
  ///
  generate
  if (NO_BULK_EP) begin : g_no_bulk_ep

  initial begin : i_no_bulk_ep
    $display("No BULK EP support");
  end

  // Tx & Rx USB handshake packets
  assign hsk_send_o = ctl_hsk_send_i;
  assign hsk_type_o = HSK_ACK; // todo: ...
  assign ctl_hsk_sent_o = hsk_sent_i;

  assign ctl_hsk_recv_o = hsk_recv_i;
  assign ctl_hsk_type_o = hsk_type_i;

  // Tx & Rx USB data packets
  assign usb_send_o = ctl_dat_send_i;
  assign usb_type_o = ctl_dat_type_i;
  assign ctl_dat_sent_o = usb_sent_i;

  assign ctl_dat_recv_o = usb_recv_i;
  assign ctl_dat_type_o = usb_type_i;
  assign ctl_dat_busy_o = usb_busy_i;

  // AXI4-Streams for the data-paths
  assign ctl_tvalid_o = 1'b0; // usb_tready_i;
  assign usb_tready_o = 1'b1;  // todo: ...
  assign ctl_tlast_o  = 1'b0;
  assign ctl_tdata_o  = 8'h00;

  assign usb_tvalid_o = ctl_tvalid_i;
  assign ctl_tready_o = usb_tready_i;
  assign usb_tlast_o  = ctl_tlast_i;
  assign usb_tdata_o  = ctl_tdata_i;

  end else begin : g_has_bulk_ep

  //
  //  TODO
  ///

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
      end else begin
        // todo: ...
      end
    end


  // -- Datapath to the USB Packet Encoder (for IN Transfers) -- //

  reg trn_zero_q;  // zero-size data transfer ??
  reg trn_send_q;
  reg [1:0] trn_type_q;

  assign usb_send_o = trn_send_q;
  assign usb_type_o = trn_type_q;

    always @(posedge clock) begin
      if (reset || usb_busy_i) begin
        trn_zero_q <= 1'b0;
        trn_send_q <= 1'b0;
        trn_type_q <= 2'bxx;
      end else begin
        case (state)
          ST_IDLE: begin
          end
          default: begin
            trn_zero_q <= trn_zero_q;
            trn_send_q <= trn_send_q;
            trn_type_q <= trn_type_q;
          end
        endcase
      end
    end

  end
  endgenerate


  // -- Transaction FSM -- //

  //
  // Hierarchical, pipelined FSM that just enables the relevant lower-level FSM,
  // waits for it to finish, or handles any errors.
  //
  // Todo: should this FSM handle no-data responses ??
  //

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
          end else if (ctl_done_i) begin
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


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_BULK: dbg_state = "BULK";
      ST_CTRL: dbg_state = "CTRL";
      ST_DUMP: dbg_state = "DUMP";
      default: dbg_state = "XXXX";
    endcase
  end

`endif


endmodule // transactor
