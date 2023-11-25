`timescale 1ns / 100ps
module fake_usb_host_ulpi (  /*AUTOARG*/
    // Outputs
    ulpi_clock_o,
    ulpi_dir_o,
    ulpi_nxt_o,
    usb_sof_o,
    crc_err_o,
    dev_enum_done_o,
    // Inouts
    ulpi_data_io,
    // Inputs
    clock,
    reset,
    ulpi_rst_ni,
    ulpi_stp_i,
    dev_enum_start_i
);

  input clock;
  input reset;

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
  output dev_enum_done_o;


  // -- Constants & Settings -- //

  localparam HIGH_SPEED = 1;
  localparam TOKEN = 1;


  // -- State & Signals -- //

  reg sready, hsend, tstart, tvalid, tlast;
  wire svalid, slast, hdone, tready;
  reg [1:0] htype, ttype;
  reg [7:0] tdata;
  wire [7:0] sdata;

  reg udir_q, unxt_q;  // ULPI signals
  reg [7:0] udat_q;

  reg hsend_q, ksend_q;
  reg [1:0] htype_q, ktype_q;
  reg [15:0] kdata_q;
  wire hdone_w, kdone_w;

  wire usb_rx_tvalid_w, usb_rx_tready_w, usb_rx_tlast_w;
  wire usb_tx_tvalid_w, usb_tx_tready_w, usb_tx_tlast_w;
  wire [7:0] usb_rx_tdata_w, usb_tx_tdata_w;

  wire tok_recv_w, rx_hrecv_w;
  wire [1:0] tok_type_w, rx_htype_w;
  wire [6:0] tok_addr_w;
  wire [3:0] tok_endp_w;


  // -- Input/Output Assignments -- //

  assign ulpi_clock_o = ~clock;
  assign ulpi_dir_o   = udir_q;
  assign ulpi_nxt_o   = unxt_q;
  assign ulpi_data_io = udir_q ? udat_q : 8'bz;


  // -- Fake ULPI -- //

  localparam ST_INIT = 4'h0;
  localparam ST_RSTN = 4'h0;
  localparam ST_IDLE = 4'hf;

  reg [3:0] state;
  integer count;
  wire [31:0] cnext = count + 1;

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_INIT;
    end else begin
      case (state)
        ST_INIT: begin
          if (!ulpi_rst_ni) begin
            state <= ST_RSTN;
            count <= 0;
          end
        end

        ST_RSTN: begin
          if (ulpi_rst_ni) begin
            count <= cnext;
            if (cnext == 200) begin
              state <= ST_IDLE;
            end
          end
        end

        default: begin
        end
      endcase
    end
  end


  // -- USB Packet Operations -- //

  wire mvalid, mready, mend;
  wire [1:0] mtype, usb_rx_ttype_w;
  wire hrecv, tdone;
  wire [7:0] mdata;
  reg xready = 1'b1;

  encode_packet #(
      .TOKEN(TOKEN)
  ) U_TX_USB_PACKET0 (
      .reset(reset),
      .clock(clock),

      .tx_tvalid_o(svalid),
      .tx_tready_i(sready),
      .tx_tlast_o (slast),
      .tx_tdata_o (sdata),

      .hsk_send_i(hsend_q),
      .hsk_done_o(hdone_w),
      .hsk_type_i(htype_q),

      .tok_send_i(ksend_q),
      .tok_done_o(kdone_w),
      .tok_type_i(ktype_q),
      .tok_data_i(kdata_q),

      .trn_tsend_i (tstart),
      .trn_ttype_i (ttype),
      .trn_tdone_o (tdone),
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


endmodule  // fake_usb_host_ulpi
