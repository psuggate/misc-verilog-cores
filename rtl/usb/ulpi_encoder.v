`timescale 1ns / 100ps
module ulpi_encoder (
    input clock,
    input reset,

    output ulpi_enabled_o,
    output high_speed_o,
    output usb_reset_o,

    // input [1:0] LineState,

    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [3:0] s_tuser,
    input [7:0] s_tdata,

    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    output [7:0] ulpi_data
);

  `include "usb_crc.vh"

  // -- Constants -- //

  // FSM states
  localparam [7:0] TX_IDLE = 8'h01;
  localparam [7:0] TX_XPID = 8'h02;
  localparam [7:0] TX_DATA = 8'h04;
  localparam [7:0] TX_CRC0 = 8'h08;
  localparam [7:0] TX_LAST = 8'h10;
  localparam [7:0] TX_DONE = 8'h20;
  localparam [7:0] TX_REGW = 8'h40;
  localparam [7:0] TX_WAIT = 8'h80;


  // -- Signals & State -- //

  reg [7:0] xsend;
  wire HighSpeed;

  wire [1:0] LineState, VbusState, RxEvent;

  // Signals for sending initialisation commands & settings to the PHY.
  reg phy_done_q, stp_q;
  wire phy_write_w, phy_stop_w, phy_chirp_w, phy_busy_w;
  wire [7:0] phy_addr_w, phy_data_w;

  // Transmit datapath MUX signals
  wire [1:0] mux_sel_w;
  wire ulpi_stp_w;
  wire [7:0] usb_pid_w, usb_dat_w, axi_dat_w, crc_dat_w, phy_dat_w, ulpi_dat_w;

  wire tlast_w = tvalid ? tlast : s_tlast;  // todo: handshakes, ZDPs, and CRCs
  wire [7:0] tdata_w = tvalid ? tdata : s_tdata;


  // -- ULPI Data-Out MUX -- //

  // Sets the idle data to PID (at start of packet), or 00h for NOP
  assign usb_dat_w = xsend == TX_IDLE ? {~s_tuser, s_tuser} : 8'd0;

  // 2:1 MUX for AXI source data, whether from skid-register, or upstream
  assign axi_dat_w = tvalid && ulpi_nxt ? tdata : s_tdata;

  // 2:1 MUX for CRC16 bytes, to be appended to USB data packets being sent
  assign crc_dat_w = xsend == TX_CRC0 ? crc16_nw[15:8] : crc16_nw[7:0];

  // 2:1 MUX for request-data to the PHY
  assign phy_dat_w = phy_chirp_w ? 8'h40 : xsend == TX_REGW ? phy_data_w : phy_addr_w;

  // Determine the data-source for the 4:1 MUX
  assign mux_sel_w = xsend == TX_IDLE ? (phy_write_w || phy_chirp_w ? 2'd2 :
                                         tvalid_w ? 2'd1 : 2'd3) :
                     xsend == TX_DATA || xsend == TX_LAST ? 2'd0 :
                     xsend == TX_REGW ? 2'd2 :
                     xsend == TX_CRC0 ? 2'd1 : 2'd3;

  mux4to1 #(
      .WIDTH(9)
  ) U_DMUX0 (
      .S(mux_sel_w),
      .O({ulpi_stp_w, ulpi_dat_w}),

      .I0({1'b0, axi_dat_w}),
      .I1({1'b0, crc_dat_w}),
      .I2({1'b0, phy_dat_w}),
      .I3({stp_q, usb_dat_w})  // NOP (or STOP)
  );


  always @(posedge clock) begin
    if (reset) begin
      ulpi_data <= 8'd0;
      ulpi_stp  <= 1'b0;
    end else begin
      ulpi_data <= ulpi_dat_w;
      ulpi_stp  <= ulpi_stp_w;
    end
  end


  // -- ULPI Encoder FSM -- //

  always @(posedge clock) begin
    if (dir_q || ulpi_dir) begin
      xsend <= TX_IDLE;
    end else begin
      case (xsend)
        default: begin  // TX_IDLE
          xsend  <= phy_cmd_w ? TX_REGW : s_tvalid ? TX_XPID : TX_IDLE;

          // Upstream TREADY signal
          rdy_q  <= phy_cmd_w || s_tvalid ? 1'b0 : HighSpeed;

          // Latch the first byte (using temp. reg.)
          // todo: move to dedicated AXI datapath
          tvalid <= rdy_q && s_tvalid;
          tlast  <= s_tlast;
          tdata  <= s_tdata;
        end

        TX_XPID: begin
          // Output PID has been accepted? If so, we can receive another byte.
          xsend <= ulpi_nxt ? TX_DATA : xsend;
          rdy_q <= ulpi_nxt ? 1'b1 : 1'b0;
        end

        TX_DATA: begin
          // Continue transferring the packet data
          xsend <= ulpi_nxt && tlast_w ? TX_CRC0 : xsend;
          rdy_q <= sready_next;
        end

        TX_CRC0: begin
          // Send 1st CRC16 byte
          xsend <= ulpi_nxt ? TX_LAST : xsend;
          rdy_q <= 1'b0;
        end

        TX_LAST: begin
          // Send 2nd (and last) CRC16 byte
          xsend <= ulpi_nxt ? TX_DONE : xsend;
          rdy_q <= 1'b0;
        end

        TX_DONE: begin
          // Wait for the PHY to signal that the USB LineState represents End-of
          // -Packet (EOP), indicating that the packet has been sent
          //
          // Todo: the USB 2.0 spec. also gives a tick-count until the packet is
          //   considered to be sent ??
          // Todo: should get the current 'LineState' from the ULPI decoder
          //   module, as this module is Tx-only ??
          //
          xsend <= dir_q && ulpi_dir && !ulpi_nxt && LineState == LS_EOP ? TX_IDLE : xsend;
          rdy_q <= 1'b0;
        end

        TX_REGW: begin
          // Write to a PHY register
          xsend <= ulpi_nxt ? TX_WAIT : xsend;
          rdy_q <= 1'b0;
        end

        TX_WAIT: begin
          // Wait for the PHY to accept a 'ulpi_data' value
          xsend <= ulpi_nxt ? TX_IDLE : xsend;
          rdy_q <= 1'b0;
        end

      endcase
    end
  end


  // -- ULPI Initialisation FSM -- //

  assign phy_busy_w = xsend != TX_IDLE;

  always @(posedge clock) begin
    phy_done_q <= xsend == TX_WAIT && ulpi_nxt;
  end


  ulpi_line_state #(
      .HIGH_SPEED(1)
  ) U_ULPI_LS0 (
      .clock(clock),
      .reset(reset),

      .LineState(LineState),
      .VbusState(VbusState),
      .RxEvent  (RxEvent),

      .ulpi_dir (ulpi_dir),
      .ulpi_nxt (ulpi_nxt),
      .ulpi_data(ulpi_data),

      .high_speed_o(high_speed_o),
      .usb_reset_o (usb_reset_o),

      .phy_write_o(phy_write_w),
      .phy_nopid_o(phy_chirp_w),
      .phy_stop_o (phy_stop_w),
      .phy_busy_i (phy_busy_w),
      .phy_done_i (phy_done_q),
      .phy_addr_o (phy_addr_w),
      .phy_data_o (phy_data_w)
  );


endmodule  // ulpi_encoder
