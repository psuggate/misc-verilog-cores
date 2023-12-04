`timescale 1ns / 100ps
module bulk_transfer
 (
  input clock,
  input reset,

  // Configured device address (or all zero)
  input [6:0] usb_addr_i,

  input fsm_bulk_i,
  input fsm_idle_i,
  output blk_done_o,

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
  output blk_start_o,
  output blk_cycle_o,
  output [3:0] blk_endpt_o,
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


  // -- Module Constants -- //

  localparam [1:0] TOK_OUT = 2'b00;
  localparam [1:0] TOK_SOF = 2'b01;
  localparam [1:0] TOK_IN = 2'b10;
  localparam [1:0] TOK_SETUP = 2'b11;

  localparam [1:0] HSK_ACK = 2'b00;
  localparam [1:0] HSK_NAK = 2'b10;

  localparam [1:0] DATA0 = 2'b00;
  localparam [1:0] DATA1 = 2'b10;

  localparam BLK_IDLE = 0;
  localparam BLK_DATI_TX = 1;
  localparam BLK_DATI_ACK = 2;
  localparam BLK_DATO_RX = 3;
  localparam BLK_DATO_ACK = 4;


  // -- State & Signals -- //

  reg [3:0] state;


  // -- Main Bulk-Transfer FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      state <= BLK_IDLE;
    end else begin
      case (state)
        default: begin // BLK_IDLE
        end
      endcase
    end
  end


endmodule // bulk_transfer
