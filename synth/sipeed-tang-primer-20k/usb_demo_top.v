`timescale 1ns / 100ps
module usb_demo_top (
    // Clock and reset from the dev-board
    input clk_26,
    input rst_n,

    output [5:0] leds,

    input  uart_rx,
    output uart_tx,

    // USB ULPI pins on the dev-board
    input ulpi_clk,
    output ulpi_rst,
    input ulpi_dir,
    input ulpi_nxt,
    output ulpi_stp,
    inout [7:0] ulpi_data
);

  // -- Constants -- //

  parameter integer SERIAL_LENGTH = 8;
  parameter [SERIAL_LENGTH*8-1:0] SERIAL_STRING = "TART0001";

  parameter [15:0] VENDOR_ID = 16'hF4CE;
  parameter integer VENDOR_LENGTH = 19;
  parameter [VENDOR_LENGTH*8-1:0] VENDOR_STRING = "University of Otago";

  parameter [15:0] PRODUCT_ID = 16'h0003;
  parameter integer PRODUCT_LENGTH = 8;
  parameter [PRODUCT_LENGTH*8-1:0] PRODUCT_STRING = "TART USB";

  // USB configuration
  localparam FPGA_VENDOR = "gowin";
  localparam FPGA_FAMILY = "gw2a";

  localparam HIGH_SPEED = 1'b1;
  localparam ULPI_DDR_MODE = 0;  // todo: '1' is way too fussy


  // -- Signals -- //

  // Globalists //
  wire clock, reset, usb_clock, usb_reset;
  wire ddr_clock, locked;
  wire [3:0] cbits;

  assign leds = {~cbits[3:0], 2'b11};


  // -- System Clocks & Resets -- //

  ulpi_reset #(
      .PHASE("0111"),
      // .PHASE("1000"),
      .PLLEN(ULPI_DDR_MODE)
  ) U_RESET0 (
      .areset_n (rst_n),
      .ulpi_clk (ulpi_clk),
      .sys_clock(clk_26),

      .ulpi_rst_n(ulpi_rst),  // Active LO
      .pll_locked(locked),

      .usb_clock(clock),  // 60 MHz, PLL output, phase-shifted
      .usb_reset(reset),  // Active HI
      .ddr_clock(ddr_clock)  // 120 MHz, PLL output, phase-shifted
  );


  // For a Basic LED Flasher //
  reg [31:0] pcount;

  always @(posedge clock) begin
    pcount <= pcount + 1;
  end

  // Local Signals //
  wire device_usb_idle_w, crc_error_w, usb_hs_enabled_w;
  wire usb_sof, configured, blk_cycle_w, has_telemetry_w, timeout_w;

  // Data-path //
  wire s_tvalid, s_tready, s_tlast;
  wire [7:0] s_tdata;

  wire m_tvalid, m_tready, m_tlast, m_tkeep;
  wire [ 7:0] m_tdata;

  // FIFO state //
  wire [10:0] level_w;
  reg bulk_in_ready_q, bulk_out_ready_q;


  // -- USB ULPI Bulk transfer endpoint (IN & OUT) -- //

  assign m_tkeep = m_tvalid;  // todo: ...


  //
  // Core Under New Tests
  ///
  ulpi_axis_bridge #(
      .VENDOR_ID(VENDOR_ID),
      .VENDOR_LENGTH(VENDOR_LENGTH),
      .VENDOR_STRING(VENDOR_STRING),
      .PRODUCT_ID(PRODUCT_ID),
      .PRODUCT_LENGTH(PRODUCT_LENGTH),
      .PRODUCT_STRING(PRODUCT_STRING),
      .SERIAL_LENGTH(SERIAL_LENGTH),
      .SERIAL_STRING(SERIAL_STRING),
      .EP1_CONTROL(0),
      .ENDPOINT1(1),
      .EP2_CONTROL(0),
      .ENDPOINT2(2)
  ) U_ULPI_USB0 (
      .areset_n(~reset),

      .ulpi_clock_i(clock),
      .ulpi_dir_i  (ulpi_dir),
      .ulpi_nxt_i  (ulpi_nxt),
      .ulpi_stp_o  (ulpi_stp),
      .ulpi_data_io(ulpi_data),

      .usb_clock_o(usb_clock),
      .usb_reset_o(usb_reset),

      .configured_o(configured),
      .has_telemetry_o(has_telemetry_w),
      .usb_hs_enabled_o(usb_hs_enabled_w),
      .usb_idle_o(device_usb_idle_w),
      .usb_sof_o(usb_sof),
      .crc_err_o(crc_error_w),
      .timeout_o(timeout_w),

      // USB bulk endpoint data-paths
      .blk_in_ready_i(bulk_in_ready_q),
      .blk_out_ready_i(bulk_out_ready_q),
      .blk_start_o(),
      .blk_cycle_o(blk_cycle_w),
      .blk_endpt_o(),
      .blk_error_i(1'b0),

      .s_axis_tvalid_i(m_tvalid && blk_cycle_w),
      .s_axis_tready_o(m_tready),
      .s_axis_tlast_i (m_tlast),
      .s_axis_tkeep_i (m_tkeep),
      .s_axis_tdata_i (m_tdata),

      .m_axis_tvalid_o(s_tvalid),
      .m_axis_tready_i(s_tready && blk_cycle_w),
      .m_axis_tlast_o (s_tlast),
      .m_axis_tdata_o (s_tdata)
  );


  // -- Loop-back FIFO for Testing -- //

  generate
    if (1) begin : g_sync_fifo

      sync_fifo #(
          .WIDTH (9),
          .ABITS (11),
          .OUTREG(3)
      ) U_BULK_FIFO0 (
          .clock(usb_clock),
          .reset(usb_reset),

          .level_o(level_w),

          .valid_i(s_tvalid && blk_cycle_w),
          .ready_o(s_tready),
          .data_i ({s_tlast, s_tdata}),

          .valid_o(m_tvalid),
          .ready_i(m_tready && blk_cycle_w),
          .data_o ({m_tlast, m_tdata})
      );

    end else begin : g_axis_fifo

      axis_fifo #(
          .DEPTH(2048),
          .DATA_WIDTH(8),
          .KEEP_ENABLE(0),
          .KEEP_WIDTH(1),
          .LAST_ENABLE(1),
          .ID_ENABLE(0),
          .ID_WIDTH(1),
          .DEST_ENABLE(0),
          .DEST_WIDTH(1),
          .USER_ENABLE(0),
          .USER_WIDTH(1),
          .RAM_PIPELINE(1),
          .OUTPUT_FIFO_ENABLE(0),
          .FRAME_FIFO(0),
          .USER_BAD_FRAME_VALUE(0),
          .USER_BAD_FRAME_MASK(0),
          .DROP_BAD_FRAME(0),
          .DROP_WHEN_FULL(0)
      ) U_BULK_FIFO0 (
          .clk(usb_clock),
          .rst(usb_reset),

          // AXI input
          .s_axis_tdata(s_tdata),
          .s_axis_tkeep(1'b1),
          .s_axis_tvalid(s_tvalid && blk_cycle_w),
          .s_axis_tready(s_tready),
          .s_axis_tlast(s_tlast),
          .s_axis_tid(1'b0),
          .s_axis_tdest(1'b0),
          .s_axis_tuser(1'b0),

          .pause_req(0),

          // AXI output
          .m_axis_tdata(m_tdata),
          .m_axis_tkeep(),
          .m_axis_tvalid(m_tvalid),
          .m_axis_tready(m_tready && blk_cycle_w),
          .m_axis_tlast(m_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),
          // Status
          .status_depth(level_w),
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end
  endgenerate


  // --Bulk Endpoint Status -- //

  always @(posedge usb_clock) begin
    if (usb_reset) begin
      bulk_in_ready_q <= 1'b0;
    end else begin
      bulk_in_ready_q  <= configured && level_w > 4;
      bulk_out_ready_q <= configured && level_w < 1024;
    end
  end


  // -- LEDs Stuffs -- //

  // Miscellaneous
  reg [23:0] count;
  reg [31:0] ucount, dcount;
  reg sof_q, ctl_latch_q = 0, crc_error_q = 0;
  reg  blk_valid_q = 0;

  wire blinky_w = crc_error_q ? count[10] & count[11] : count[12];
  wire ctl0_error_w = U_ULPI_USB0.ctl0_error_w;

  wire xfer_state_w = U_ULPI_USB0.U_TRANSACT1.xfer_idle_w;
  wire xfer_error_w = U_ULPI_USB0.U_TRANSACT1.xfer_dzdp_w && bulk_in_ready_q;
  // wire xfer_error_w = U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xfer_dzdp_w || U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xfer_derr_w;
  // wire xfer_error_w = U_ULPI_USB0.U_USB_CTRL0.U_USB_TRN0.xfer_derr_w;

  // assign cbits = {ucount[24], pcount[24], ulpi_rst, locked};
  // assign cbits = {blinky_w, ctl_latch_q, xfer_state_w, blk_valid_q};
  assign cbits = U_ULPI_USB0.U_LINESTATE1.state;
  // wire [11:0] xsend;
  // assign xsend = U_ULPI_USB0.enc_state_w;
  // assign cbits = xsend[11:8];

  always @(posedge usb_clock) begin
    if (usb_reset) begin
      ctl_latch_q <= 1'b0;
      // end else if (U_ULPI_USB0.U_USB_CTRL0.U_DECODER0.tok_ping_q) begin
      // end else if (xfer_error_w) begin
    end else if (timeout_w) begin
      ctl_latch_q <= 1'b1;
    end

    /*
    if (ctl0_error_w) begin
      ctl_latch_q <= 1'b1;
    end

    if (usb_reset) begin
      blk_valid_q <= 1'b0;
    end else begin
      blk_valid_q <= bulk_in_ready_q || bulk_out_ready_q;  // m_tvalid;
    end
     */

    blk_valid_q <= has_telemetry_w;

    if (usb_reset) begin
      crc_error_q <= 1'b0;
    end else if (crc_error_w) begin
      crc_error_q <= 1'b1;
    end
  end


  always @(posedge usb_clock) begin
    if (usb_reset) begin
      count <= 0;
      sof_q <= 1'b0;
    end else begin
      sof_q <= usb_sof;

      if (usb_sof && !sof_q) begin
        count <= count + 1;
      end
    end
  end

  always @(posedge ulpi_clk) begin
    ucount <= ucount + 1;
  end

  always @(posedge clock) begin
    pcount <= pcount + 1;
  end


  //
  //  Status via UART
  ///
  // localparam [15:0] UART_PRESCALE = 16'd65; // For: 60.0 MHz / (115200 * 8)
  // localparam [15:0] UART_PRESCALE = 16'd781;  // For: 60.0 MHz / (9600 * 8)
  localparam [15:0] UART_PRESCALE = 16'd3125;  // For: 60.0 MHz / (2400 * 8)
  localparam [63:0] UART_GARBAGES = "TART013\n";

  reg [2:0] scount;

  reg svalid, mready, merror;
  reg [7:0] sdata;
  wire sready, mvalid;
  wire [7:0] mdata, sdata_w;
  wire rx_busy_w, tx_busy_w, rx_orun_w, rx_ferr_w;
  reg [7:0] garbo[7:0];

  genvar ii;
  generate

    for (ii = 7; ii >= 0; ii--) begin : g_set_garbage_rom
      assign garbo[7 - ii] = UART_GARBAGES[ii*8+7-:8];
    end

  endgenerate

  // assign cbits   = {dcount[10], merror, rx_busy_w, tx_busy_w};
  assign sdata_w = garbo[scount];

  reg stb_q;
  reg [15:0] pre_q;
  wire [15:0] pnext;

  assign pnext = pre_q == 16'd130 ? 16'd30 : pre_q + 16'd1;

  always @(posedge clock) begin
    if (reset) begin
      stb_q <= 1'b0;
      pre_q <= UART_PRESCALE;
    end else if (svalid && sready && dcount[10] && !stb_q) begin
      pre_q <= pnext;
      stb_q <= 1'b1;
    end else if (!dcount[10]) begin
      stb_q <= 1'b0;
    end
  end


  //
  //  Produce an endless stream of garbage
  ///
`define __capture_telemetry
`ifdef __capture_telemetry

  wire fready, xvalid, xready;
  wire [7:0] fdata, xdata;

  reg tstart, tcycle;
  wire terror;
  wire [9:0] tlevel;
  wire tvalid, tlast, tkeep;
  reg tready;
  wire [7:0] tdata;

  always @(posedge clock) begin
    if (reset) begin
      dcount <= 0;
      merror <= 1'b0;
    end else begin
      if (xvalid && xready) begin
        dcount <= dcount + 1;
      end
      if (rx_orun_w || rx_ferr_w) begin
        merror <= 1'b1;
      end
    end
  end


  // -- Telemetry Read-Back Logic -- //

  wire uvalid, uready;
  wire [7:0] udata, tbyte0_w, tbyte1_w;
  reg fvalid, flast;
  reg [3:0] tindex;
  reg [7:0] tbyte0, tbyte1, tbyte2, tbyte3, wspace;

  assign tbyte0_w = (tdata[3:0] < 4'd10 ? 8'd48 : 8'd65) + tdata[3:0];
  assign tbyte1_w = (tdata[7:4] < 4'd10 ? 8'd48 : 8'd65) + tdata[7:4];
  assign uready = ~tcycle;
  assign fdata = tindex == 4'h3 ? 8'd0 :
                 tindex == 4'h4 ? tbyte3 :
                 tindex == 4'h5 ? 8'd0 :
                 tindex == 4'h6 ? tbyte2 :
                 tindex == 4'h7 ? 8'd0 :
                 tindex == 4'h8 ? tbyte1 :
                 tindex == 4'h9 ? 8'd0 :
                 tindex == 4'ha ? tbyte0 :
                 tindex == 4'hb ? 8'd0 :
                 tindex == 4'hc ? wspace :
                 "-";

  always @(posedge clock) begin
    if (reset) begin
      tstart <= 1'b0;
      tcycle <= 1'b0;
      tready <= 1'b0;
      tindex <= 4'h0;
      fvalid <= 1'b0;
      flast  <= 1'b0;
    end else begin
      case (tindex)
        4'h0: begin
          fvalid <= 1'b0;
          flast  <= 1'b0;
          if (uvalid && udata == "a") begin
            tstart <= 1'b1;
            tcycle <= 1'b1;
            tready <= 1'b1;
            tindex <= 4'h1;
          end else begin
            tstart <= 1'b0;
            tcycle <= 1'b0;
            tready <= 1'b0;
          end
        end
        4'h1: begin
          tstart <= 1'b0;
          fvalid <= 1'b0;
          if (tvalid && tkeep && tready) begin
            tready <= 1'b1;
            tindex <= 4'h2;
            tbyte0 <= tbyte0_w;
            tbyte1 <= tbyte1_w;
          end
        end
        4'h2: begin
          fvalid <= 1'b0;
          flast  <= tvalid && tlast && tready;
          if (tvalid && tkeep && tready) begin
            tready <= 1'b0;
            tindex <= 4'h3;
            tbyte2 <= tbyte0_w;
            tbyte3 <= tbyte1_w;
            wspace <= tlast ? "\n" : " ";
          end
        end
        4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9, 4'ha, 4'hb: begin
          fvalid <= 1'b1;
          if (fvalid && fready) begin
            tindex <= tindex + 4'h1;
          end
        end
        4'hc: begin
          // Decide whether there are more bytes, or if the packet has been
          // completed
          if (fvalid && fready) begin
            tready <= ~flast;
            tindex <= flast ? 4'hd : 4'h1;
            fvalid <= 1'b0;
          end else begin
            fvalid <= 1'b1;
          end
        end
        4'hd: begin
          // Wait for the packet to be sent
          tcycle <= 1'b0;
          if (!xvalid) begin
            tindex <= 4'h0;
          end
        end
      endcase
    end
  end


  // -- Telemetry Logger -- //

  wire [3:0] usb_state_w = U_ULPI_USB0.U_TRANSACT1.xfer_state_w;
  wire [3:0] ctl_state_w = U_ULPI_USB0.U_TRANSACT1.xctrl;
  wire [7:0] blk_state_w = U_ULPI_USB0.U_TRANSACT1.xbulk;


  // Capture telemetry, so that it can be read back from EP1
  bulk_telemetry #(
      .ENDPOINT(4'd2)
  ) U_TELEMETRY1 (
      .clock(clock),
      .reset(1'b0),
      .usb_enum_i(1'b1),

      .crc_error_i(crc_error_w),
      .usb_state_i(usb_state_w),
      .ctl_state_i(ctl_state_w),
      .blk_state_i(blk_state_w),

      .start_i (tstart),
      .select_i(tcycle),
      .endpt_i (4'd2),
      .error_o (terror),
      .level_o (tlevel),

      // Unused
      .s_tvalid(1'b0),
      .s_tready(),
      .s_tlast (1'b0),
      .s_tkeep (1'b0),
      .s_tdata (8'hx),

      // AXI4-Stream for telemetry data
      .m_tvalid(tvalid),
      .m_tlast (tlast),
      .m_tkeep (tkeep),
      .m_tdata (tdata),
      .m_tready(tready)
  );

  sync_fifo #(
      .WIDTH (8),
      .ABITS (11),
      .OUTREG(3)
  ) U_UART_FIFO1 (
      .clock(clock),
      .reset(reset),

      .level_o(),

      .valid_i(fvalid),
      .ready_o(fready),
      .data_i (fdata),

      .valid_o(xvalid),
      .ready_i(xready),
      .data_o (xdata)
  );


  uart #(
      .DATA_WIDTH(8)
  ) U_UART1 (
      .clk(clock),
      .rst(reset),

      .s_axis_tvalid(xvalid),
      .s_axis_tready(xready),
      .s_axis_tdata (xdata),

      .m_axis_tvalid(uvalid),
      .m_axis_tready(uready),
      .m_axis_tdata (udata),

      .rxd(uart_rx),
      .txd(uart_tx),

      .rx_busy(rx_busy_w),
      .tx_busy(tx_busy_w),
      .rx_overrun_error(rx_orun_w),
      .rx_frame_error(rx_ferr_w),

      .prescale(UART_PRESCALE)
  );

`else

  wire [7:0] line_state = 8'd48 + U_ULPI_USB0.U_LINESTATE1.LineStateW;
  wire [7:0] init_state = 8'd65 + U_ULPI_USB0.U_LINESTATE1.state;

  always @(posedge clock) begin
    if (reset || 1'b1) begin
      svalid <= 1'b0;
      sdata  <= UART_GARBAGES[7:0];
      scount <= 3'd1;
      mready <= 1'b0;
      merror <= 1'b0;
      dcount <= 0;
    end else begin
      mready <= 1'b1;
      if (rx_orun_w || rx_ferr_w || mvalid && mdata == 8'd99) begin
        merror <= 1'b1;
      end else if (mvalid && mdata == 8'd120) begin
        merror <= 1'b0;
      end

      if (svalid && sready) begin
        svalid <= 1'b0;
      end else if (!tx_busy_w && !svalid && sready) begin
        svalid <= 1'b1;
        if (!dcount[0]) begin
          sdata <= 8'd0;
        end else begin
          // sdata <= sdata_w;
          case (scount)
            3'd0: sdata <= 8'd84;
            3'd1: sdata <= line_state;
            3'd2: sdata <= 8'd82;
            3'd3: sdata <= init_state;
            3'd4: sdata <= 8'd48;
            3'd5: sdata <= 8'd49;
            3'd6: sdata <= 8'd48;
            default: sdata <= 8'd10;
          endcase
          scount <= scount + 3'd1;
        end
        dcount <= dcount + 1;
      end
    end
  end


  uart #(
      .DATA_WIDTH(8)
  ) U_UART1 (
      .clk(clock),
      .rst(reset),

      .s_axis_tvalid(svalid),
      .s_axis_tready(sready),
      .s_axis_tdata (sdata),

      .m_axis_tvalid(mvalid),
      .m_axis_tready(mready),
      .m_axis_tdata (mdata),

      .rxd(uart_rx),
      .txd(uart_tx),

      .rx_busy(rx_busy_w),
      .tx_busy(tx_busy_w),
      .rx_overrun_error(rx_orun_w),
      .rx_frame_error(rx_ferr_w),

      // .prescale(pre_q)
      .prescale(UART_PRESCALE)
  );

`endif


endmodule  // usb_demo_top
