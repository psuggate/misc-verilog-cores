`timescale 1ns / 100ps
`define SERIAL_NUMBER "BULK0000"
/**
 * Top-level USB ULPI Bulk transfer endpoint (IN and/or OUT) core.
 *
 * Note: Data from/to this core is via AXI4 Stream interconnects.
 */
module ulpi_bulk_axis (
    ulpi_clock_i,
    ulpi_reset_o,
    ulpi_dir_i,
    ulpi_nxt_i,
    ulpi_stp_o,
    ulpi_data_t,
    ulpi_data_i,
    ulpi_data_o,

    aclk,
    aresetn,

    /* Status flags */
    fifo_in_full_o,
    fifo_out_full_o,
    fifo_has_data_o,
    usb_sof_o,

    s_axis_tvalid_i,
    s_axis_tready_o,
    s_axis_tlast_i,
    s_axis_tdata_i,

    m_axis_tvalid_o,
    m_axis_tready_i,
    m_axis_tlast_o,
    m_axis_tdata_o
);

  parameter FPGA_VENDOR = "gowin";  // todo: keep this, and add "gowin"?
  parameter FPGA_FAMILY = "gw2a";
  parameter [15:0] VENDOR_ID = 16'hF4CE;
  parameter [15:0] PRODUCT_ID = 16'h0003;

  // USB configuration
  parameter HIGH_SPEED = 1;  /* 0 - Full-Speed; 1 - High-Speed */
  parameter [63:0] SERIAL_NUMBER = `SERIAL_NUMBER;
  parameter CHANNEL_IN_ENABLE = 1;  /* 0 - Disable; 1 - Enable */
  parameter CHANNEL_OUT_ENABLE = 1;  /* 0 - Disable; 1 - Enable */

  parameter PACKET_MODE = 0;  /* 0 - Stream Mode; 1 - Packet Mode */

  /* UTMI Low Pin Interface Ports */
  input wire ulpi_clock_i;
  output wire ulpi_reset_o;

  input wire ulpi_dir_i;
  input wire ulpi_nxt_i;
  output wire ulpi_stp_o;
  output wire ulpi_data_t;
  input wire [7:0] ulpi_data_i;
  output wire [7:0] ulpi_data_o;

  /* AXI4-Stream Interface */
  input wire aclk;
  input wire aresetn;

  /* Status flags */
  output wire fifo_in_full_o;
  output wire fifo_out_full_o;
  output wire fifo_has_data_o;
  output wire usb_sof_o;

  input wire s_axis_tvalid_i;
  output wire s_axis_tready_o;
  input wire s_axis_tlast_i;
  input wire [7:0] s_axis_tdata_i;

  output wire m_axis_tvalid_o;
  input wire m_axis_tready_i;
  output wire m_axis_tlast_o;
  output wire [7:0] m_axis_tdata_o;


  function [15:0] config_channel;
    input integer enable;
    input integer width;
    input integer endian;
    input integer fifo_enable;
    input integer fifo_packet;
    input integer fifo_depth;
    reg [4:0] log_value;
    begin

      config_channel = 16'h0000;

      case (enable)
        0: config_channel[0] = 1'b0;
        1: config_channel[0] = 1'b1;
        default: config_channel[0] = 1'b0;
      endcase

      case (width)
        8: config_channel[2:1] = 2'b01;
        16: config_channel[2:1] = 2'b10;
        32: config_channel[2:1] = 2'b11;
        default: config_channel[2:1] = 2'b00;
      endcase

      case (endian)
        0: config_channel[3] = 1'b0;
        1: config_channel[3] = 1'b1;
        default: config_channel[3] = 1'b0;
      endcase

      case (fifo_enable)
        0: config_channel[4] = 1'b0;
        1: config_channel[4] = 1'b1;
        default: config_channel[4] = 1'b0;
      endcase

      case (fifo_packet)
        0: config_channel[5] = 1'b0;
        1: config_channel[5] = 1'b1;
        default: config_channel[5] = 1'b0;
      endcase

      log_value = $clog2(fifo_depth);
      config_channel[10:6] = log_value;

    end
  endfunction

  localparam [15:0] CONFIG_CHAN_IN = config_channel(CHANNEL_IN_ENABLE, 8, 0, 0, 0, 0);
  localparam [15:0] CONFIG_CHAN_OUT = config_channel(CHANNEL_OUT_ENABLE, 8, 0, 0, 0, 0);


  // todo: this is what 'axis_usbd' uses, but check the ULPI specs/timing diagrams
  assign ulpi_data_t = ulpi_dir_i;

  bulk_ep_axis_bridge #(
      .FPGA_VENDOR(FPGA_VENDOR),
      .FPGA_FAMILY(FPGA_FAMILY),
      .VENDOR_ID(VENDOR_ID),
      .PRODUCT_ID(PRODUCT_ID),
      .MANUFACTURER_LEN(19),
      .MANUFACTURER("University of Otago"),
      .PRODUCT_LEN(15),
      .PRODUCT("AXIS USB Bridge"),
      .SERIAL(SERIAL_NUMBER),
      .HIGH_SPEED(HIGH_SPEED),
      .PACKET_MODE(PACKET_MODE),
      .CONFIG_CHAN({CONFIG_CHAN_OUT, CONFIG_CHAN_IN})
  ) bulk_ep_axis_bridge_inst (
      .sys_clk(aclk),
      .reset_n(aresetn),

      .fifo_in_full_o(fifo_in_full_o),
      .fifo_out_full_o(fifo_out_full_o),
      .fifo_has_data_o(fifo_has_data_o),
      .usb_sof_o    (usb_sof_o),

      .ulpi_clk     (ulpi_clock_i),
      .ulpi_reset   (ulpi_reset_o),
      .ulpi_dir     (ulpi_dir_i),
      .ulpi_nxt     (ulpi_nxt_i),
      .ulpi_stp     (ulpi_stp_o),
      .ulpi_data_in (ulpi_data_i),
      .ulpi_data_out(ulpi_data_o),

      .s_axis_tvalid(s_axis_tvalid_i),
      .s_axis_tready(s_axis_tready_o),
      .s_axis_tlast (s_axis_tlast_i),
      .s_axis_tdata (s_axis_tdata_i),

      .m_axis_tvalid(m_axis_tvalid_o),
      .m_axis_tready(m_axis_tready_i),
      .m_axis_tlast (m_axis_tlast_o),
      .m_axis_tdata (m_axis_tdata_o)
  );

endmodule  // ulpi_bulk_axis
