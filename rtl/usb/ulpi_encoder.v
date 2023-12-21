`timescale 1ns / 100ps
module ulpi_encoder (
    input clock,
    input reset,

    input high_speed_i,

    input [1:0] LineState,
    input [1:0] VbusState,

    // Signals for controlling the ULPI PHY
    input phy_write_i,
    input phy_nopid_i,
    input phy_stop_i,
    output phy_busy_o,
    output phy_done_o,
    input [7:0] phy_addr_i,
    input [7:0] phy_data_i,

    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [3:0] s_tuser,
    input [7:0] s_tdata,

    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    output reg [7:0] ulpi_data
);

  // -- Definitions -- //

  `include "usb_crc.vh"

  function src_ready(input svalid, input tvalid, input dvalid, input dready);
    src_ready = dready || !(tvalid || (dvalid && svalid));
  endfunction


  // -- Constants -- //

  // FSM states
  localparam [8:0] TX_IDLE = 9'h001;
  localparam [8:0] TX_XPID = 9'h002;
  localparam [8:0] TX_DATA = 9'h004;
  localparam [8:0] TX_CRC0 = 9'h008;
  localparam [8:0] TX_LAST = 9'h010;
  localparam [8:0] TX_DONE = 9'h020;
  localparam [8:0] TX_REGW = 9'h040;
  localparam [8:0] TX_WAIT = 9'h080;
  localparam [8:0] TX_INIT = 9'h100;

  localparam [1:0] LS_EOP = 2'b00;


  // -- Signals & State -- //

  reg [8:0] xsend;
  reg dir_q, rdy_q;

  // Transmit datapath MUX signals
  wire [1:0] mux_sel_w;
  wire ulpi_stp_w;
  wire [7:0] usb_pid_w, usb_dat_w, axi_dat_w, crc_dat_w, phy_dat_w, ulpi_dat_w;

  reg tvalid, tlast;
  reg [7:0] tdata;
  wire tvalid_w;
  wire tlast_w = tvalid ? tlast : s_tlast;  // todo: handshakes, ZDPs, and CRCs
  wire [7:0] tdata_w = tvalid ? tdata : s_tdata;

  assign tvalid_w = 1'b0;

  reg  dvalid;
  wire sready_next;

  assign sready_next = src_ready(s_tvalid, tvalid, dvalid, ulpi_nxt);


  // -- ULPI Initialisation FSM -- //

  // Signals for sending initialisation commands & settings to the PHY.
  reg phy_done_q, stp_q;

  assign phy_busy_o = xsend != TX_INIT;
  assign phy_done_o = phy_done_q;

  assign ulpi_stp   = stp_q;

  always @(posedge clock) begin
    phy_done_q <= xsend == TX_WAIT && ulpi_nxt;
  end


  // -- Tx data CRC Calculation -- //

  reg  [15:0] crc16_q;
  wire [15:0] crc16_nw;

  genvar ii;
  generate
    for (ii = 0; ii < 16; ii++) begin : g_crc16_revneg
      assign crc16_nw[ii] = ~crc16_q[15-ii];
    end  // g_crc16_revneg
  endgenerate

  always @(posedge clock) begin
    if (TX_IDLE) begin
      crc16_q <= 16'hffff;
    end else if (s_tvalid && s_tready) begin
      crc16_q <= crc16(s_tdata, crc16_q);
    end
  end


  // -- ULPI Data-Out MUX -- //

  // Sets the idle data to PID (at start of packet), or 00h for NOP
  assign usb_dat_w = s_tvalid && xsend == TX_IDLE ? {~s_tuser, s_tuser} : 8'd0;

  // 2:1 MUX for AXI source data, whether from skid-register, or upstream
  assign axi_dat_w = tvalid && ulpi_nxt ? tdata : s_tdata;

  // 2:1 MUX for CRC16 bytes, to be appended to USB data packets being sent
  assign crc_dat_w = xsend == TX_CRC0 ? crc16_nw[15:8] : crc16_nw[7:0];

  // 2:1 MUX for request-data to the PHY
  assign phy_dat_w = phy_nopid_i ? 8'h40 :
                     xsend == TX_REGW && ulpi_nxt || xsend == TX_WAIT ? phy_data_i :
                     phy_addr_i;

  // Determine the data-source for the 4:1 MUX
  assign mux_sel_w = xsend == TX_INIT && (phy_write_i || phy_nopid_i) ? 2'd2 :
                     xsend == TX_REGW ? 2'd2 :
                     xsend == TX_IDLE ? (tvalid_w ? 2'd1 : 2'd3) :
                     xsend == TX_DATA || xsend == TX_LAST ? 2'd0 :
                     xsend == TX_CRC0 ? 2'd1 : 2'd3;

  mux4to1 #(
      .WIDTH(8)
  ) U_DMUX0 (
      .S(mux_sel_w),
      .O(ulpi_dat_w),

      .I0(axi_dat_w),
      .I1(crc_dat_w),
      .I2(phy_dat_w),
      .I3(usb_dat_w)   // NOP (or STOP)
  );


  always @(posedge clock) begin
    if (reset) begin
      ulpi_data <= 8'd0;
    end else begin
      ulpi_data <= ulpi_dat_w;
    end
  end

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
  end


  // -- ULPI Encoder FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      xsend <= TX_INIT;
    end else if (dir_q || ulpi_dir) begin
      xsend <= TX_IDLE;
    end else begin
      case (xsend)
        default: begin  // TX_IDLE
          xsend  <= phy_write_i ? TX_REGW : phy_nopid_i ? TX_WAIT : s_tvalid ? TX_XPID : TX_IDLE;
          stp_q  <= 1'b0;

          // Upstream TREADY signal
          rdy_q  <= phy_write_i || phy_nopid_i || s_tvalid ? 1'b0 : high_speed_i;

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
          stp_q <= ulpi_nxt ? 1'b1 : 1'b0;
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
          stp_q <= 1'b0;
          rdy_q <= 1'b0;
        end

        //
        //  Until the PHY has been configured, respond to the commands from the
        //  'ulpi_line_state' module.
        ///
        TX_INIT: begin
          xsend <= phy_write_i ? TX_REGW : phy_nopid_i ? TX_WAIT : xsend;
          stp_q <= phy_stop_i ? ~stp_q : 1'b0;
          rdy_q <= 1'b0;
        end

        TX_REGW: begin
          // Write to a PHY register
          xsend <= ulpi_nxt ? TX_WAIT : xsend;
          stp_q <= 1'b0;
          rdy_q <= 1'b0;
        end

        TX_WAIT: begin
          // Wait for the PHY to accept a 'ulpi_data' value
          xsend <= ulpi_nxt ? TX_INIT : xsend;
          stp_q <= ulpi_nxt ? 1'b1 : 1'b0;
          rdy_q <= 1'b0;
        end

      endcase
    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_xsend;

  always @* begin
    case (xsend)
      TX_IDLE: dbg_xsend = "IDLE";
      TX_XPID: dbg_xsend = "XPID";
      TX_DATA: dbg_xsend = "DATA";
      TX_CRC0: dbg_xsend = "CRC0";
      TX_LAST: dbg_xsend = "LAST";
      TX_DONE: dbg_xsend = "DONE";
      TX_INIT: dbg_xsend = "INIT";
      TX_REGW: dbg_xsend = "REGW";
      TX_WAIT: dbg_xsend = "WAIT";
      default: dbg_xsend = "XXXX";
    endcase
  end

`endif


endmodule  // ulpi_encoder
