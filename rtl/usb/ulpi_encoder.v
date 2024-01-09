`timescale 1ns / 100ps
module ulpi_encoder #(
    parameter OUTREG = 3
) (
    input clock,
    input reset,

    input  high_speed_i,
    output encode_idle_o,

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

    input  hsk_send_i,
    output hsk_done_o,
    output usb_busy_o,
    output usb_done_o,

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

  // -- Definitions -- //

  `include "usb_crc.vh"


  // -- Constants -- //

  // FSM states
  localparam [10:0] TX_IDLE = 11'h001;
  localparam [10:0] TX_XPID = 11'h002;
  localparam [10:0] TX_HSK0 = 11'h004;
  localparam [10:0] TX_DATA = 11'h008;
  localparam [10:0] TX_CRC0 = 11'h010;
  localparam [10:0] TX_CRC1 = 11'h020;
  localparam [10:0] TX_LAST = 11'h040;
  localparam [10:0] TX_DONE = 11'h080;
  localparam [10:0] TX_INIT = 11'h100;
  localparam [10:0] TX_REGW = 11'h200;
  localparam [10:0] TX_WAIT = 11'h400;

  localparam [1:0] LS_EOP = 2'b00;


  // -- Signals & State -- //

  reg [10:0] xsend;
  reg dir_q;
  reg phy_done_q, hsk_done_q, usb_done_q;

  // Transmit datapath MUX signals
  wire [1:0] mux_sel_w;
  wire [7:0] usb_pid_w, usb_dat_w, axi_dat_w, crc_dat_w, phy_dat_w, ulpi_dat_w;

  wire svalid_w, sready_w, tvalid_w, tready_w, tlast_w, dvalid_w, dlast_w;
  wire [7:0] ddata_w, tdata_w;


  // -- I/O Assignments -- //

  // todo: check that this encodes correctly (as 'xsend[0]') !?
  assign encode_idle_o = xsend == TX_IDLE;

  assign usb_busy_o = xsend != TX_IDLE;
  assign usb_done_o = usb_done_q;
  assign hsk_done_o = hsk_done_q;


  // -- ULPI Initialisation FSM -- //

  // Signals for sending initialisation commands & settings to the PHY.
  assign phy_busy_o = xsend != TX_INIT;
  assign phy_done_o = phy_done_q;

  always @(posedge clock) begin
    phy_done_q <= xsend == TX_WAIT && ulpi_nxt;
    hsk_done_q <= xsend == TX_DONE && ulpi_stp && hsk_send_i;
    usb_done_q <= xsend == TX_DONE && ulpi_stp && !hsk_send_i;
  end

  always @(posedge clock) begin
    dir_q <= ulpi_dir;
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
    if (reset || xsend == TX_DONE) begin
      crc16_q <= 16'hffff;
    end else if (s_tvalid && s_tready && s_tkeep) begin
      crc16_q <= crc16(s_tdata, crc16_q);
    end
  end


  // -- ULPI Encoder FSM -- //

  always @(posedge clock) begin
    if (reset) begin
      xsend <= TX_INIT;
    end else if (dir_q || ulpi_dir) begin
      xsend <= xsend;  //  == TX_XPID ? TX_IDLE : xsend;
    end else begin
      case (xsend)
        default: begin  // TX_IDLE
          xsend <= hsk_send_i ? TX_HSK0 :
                   s_tvalid ? (!s_tkeep && s_tlast ? TX_CRC0 : TX_XPID) :
                   TX_IDLE;
        end

        TX_XPID: begin
          // Output PID has been accepted? If so, we can receive another byte.
          xsend <= ulpi_nxt ? TX_DATA : xsend;
        end

        TX_DATA: begin
          // Continue transferring the packet data
          xsend <= s_tvalid && !s_tkeep && sready_w ? TX_CRC1 : s_tlast && (sready_w || !sready_w && tvalid_w && tready_w) ? TX_CRC0 : xsend;
        end

        TX_CRC0: begin
          // Send 1st CRC16 byte
          xsend <= svalid_w && sready_w ? TX_CRC1 : xsend;
        end

        TX_CRC1: begin
          // Send 2nd CRC16 byte
          xsend <= svalid_w && sready_w ? TX_LAST : xsend;
        end

        TX_LAST: begin
          // Send 2nd (and last) CRC16 byte
          xsend <= slast_w && sready_w ? TX_DONE : xsend;
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
          xsend <= !ulpi_nxt && !ulpi_stp && ulpi_data == 8'd0 ? TX_IDLE : xsend;
          // xsend <= dir_q && ulpi_dir && !ulpi_nxt && LineState == LS_EOP ? TX_IDLE : xsend;
        end

        TX_HSK0: begin
          xsend <= ulpi_nxt ? TX_DONE : xsend;
        end

        //
        //  Until the PHY has been configured, respond to the commands from the
        //  'ulpi_line_state' module.
        ///
        TX_INIT: begin
          xsend <= high_speed_i ? TX_IDLE : phy_write_i ? TX_REGW : xsend;
        end

        TX_REGW: begin
          // Write to a PHY register
          xsend <= ulpi_nxt ? TX_WAIT : xsend;
        end

        TX_WAIT: begin
          // Wait for the PHY to accept a 'ulpi_data' value
          xsend <= ulpi_nxt ? TX_INIT : xsend;
        end
      endcase
    end
  end


  // -- ULPI Data-Out MUX -- //

  wire slast_w, uvalid_w;
  wire [7:0] udata_w, sdata_w, pdata_w;

  assign usb_pid_w = {2'b01, 2'b00, s_tuser};

  assign udata_w = xsend == TX_IDLE ? usb_pid_w :
                   xsend == TX_DATA && s_tvalid && !s_tkeep ? crc16_nw[7:0] :
                   xsend == TX_CRC0 ? crc16_nw[7:0] :
                   xsend == TX_CRC1 ? crc16_nw[15:8] :
                   s_tdata;
  assign uvalid_w = s_tvalid || hsk_send_i || xsend == TX_DATA || xsend == TX_CRC0 || xsend == TX_CRC1;

  assign pdata_w = phy_nopid_i ? 8'h40 : phy_write_i ? phy_addr_i : 8'd0;

  assign svalid_w = xsend == TX_INIT ? phy_write_i || phy_nopid_i :
                    xsend == TX_IDLE ? hsk_send_i || s_tvalid :
                    xsend == TX_DATA ? sready_w :
                    xsend == TX_XPID ? s_tvalid && s_tkeep && sready_w :
                    (xsend == TX_CRC0 || xsend == TX_CRC1) && sready_w ||
                    xsend == TX_WAIT;
  assign slast_w = xsend == TX_INIT ? phy_stop_i :
                   xsend == TX_REGW ? 1'b0 :
                   xsend == TX_WAIT ? 1'b1 : ulpi_nxt && (xsend == TX_LAST || hsk_send_i);
  assign sdata_w = xsend == TX_INIT || xsend == TX_REGW ? pdata_w :
                   xsend == TX_WAIT ? 8'd0 : uvalid_w ? udata_w : 8'd0;

  // Load the 'temp. reg.' of the skid-buffer:
  //  - with ULPI PHY register value, when writing to a ULPI PHY register;
  //  - with '0x40' when issuing a 'NO PID' command; e.g., to initiate a K-chirp
  //    during High-Speed negotiation;
  //  - with '0x00' when issuing a USB handshake packet;
  //  - with 'data[0]' (and data-overflows due to flow-control), when performing
  //    USB data 'IN' transactions;
  assign tvalid_w = xsend == TX_INIT ? phy_write_i || phy_nopid_i :
                    xsend == TX_IDLE ? hsk_send_i || s_tvalid && s_tkeep :
                    1'b0;
  assign tlast_w = xsend == TX_INIT ? phy_nopid_i : xsend == TX_WAIT ? ulpi_nxt :
                   xsend == TX_IDLE && hsk_send_i ? 1'b1 :
                   xsend == TX_REGW || xsend == TX_WAIT || xsend == TX_DATA ? 1'b0 : s_tlast;
  assign tdata_w = xsend == TX_INIT || xsend == TX_REGW ? (phy_nopid_i ? 8'd0 : phy_data_i) :
                   xsend == TX_IDLE && hsk_send_i ? 8'd0 : s_tdata;

  // assign s_tready = sready_w && !ulpi_dir && high_speed_i;
  assign s_tready = sready_w && high_speed_i;


  // -- Skid Register with Loadable, Overflow Register -- //

  skid_loader #(
      .RESET_TDATA(1),
      .RESET_VALUE(8'd0),
      .WIDTH(8),
      .BYPASS(0),
      .LOADER(1)
  ) U_SKID3 (
      .clock(clock),
      .reset(reset || ulpi_dir || xsend == TX_DONE),

      .s_tvalid(svalid_w),
      .s_tready(sready_w),
      .s_tlast (slast_w),
      .s_tdata (sdata_w),

      .t_tvalid(tvalid_w),  // If OUTREG > 2, allow the temp-register to be
      .t_tready(tready_w),  // explicitly loaded
      .t_tlast (tlast_w),
      .t_tdata (tdata_w),

      .m_tvalid(),
      .m_tready(ulpi_nxt),
      .m_tlast (ulpi_stp),
      .m_tdata (ulpi_data)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [39:0] dbg_xsend;

  always @* begin
    case (xsend)
      TX_IDLE: dbg_xsend = "IDLE";
      TX_XPID: dbg_xsend = "XPID";
      TX_DATA: dbg_xsend = "DATA";
      TX_CRC0: dbg_xsend = "CRC0";
      TX_CRC1: dbg_xsend = "CRC1";
      TX_LAST: dbg_xsend = "LAST";
      TX_DONE: dbg_xsend = "DONE";
      TX_INIT: dbg_xsend = "INIT";
      TX_REGW: dbg_xsend = "REGW";
      TX_WAIT: dbg_xsend = "WAIT";
      TX_HSK0: dbg_xsend = "HSK0";
      default: dbg_xsend = "XXXX";
    endcase
  end

`endif


endmodule  // ulpi_encoder
