`timescale 1ns / 100ps
//
// The USB '0' configuration/control PIPE is always reserved for configuring a
// USB device/function.
//
// Based on project 'https://github.com/ObKo/USBCore'
// License: MIT
//  Copyright (c) 2021 Dmitry Matyunin
//  Copyright (c) 2023 Patrick Suggate
//
module ctl_pipe0 #(
    parameter [15:0] VENDOR_ID = 16'hFACE,
    parameter [15:0] PRODUCT_ID = 16'h0BDE,
    parameter MANUFACTURER_LEN = 0,
    parameter MANUFACTURER = "",
    parameter PRODUCT_LEN = 0,
    parameter PRODUCT = "",
    parameter SERIAL_LEN = 0,
    parameter SERIAL = "",
    parameter CONFIG_DESC_LEN = 18,
    parameter CONFIG_DESC = {
      /* Interface descriptor */
      8'h00,  /* iInterface */
      8'h00,  /* bInterfaceProtocol */
      8'h00,  /* bInterfaceSubClass */
      8'h00,  /* bInterfaceClass */
      8'h00,  /* bNumEndpoints = 0 */
      8'h00,  /* bAlternateSetting */
      8'h00,  /* bInterfaceNumber = 0 */
      8'h04,  /* bDescriptorType = Interface Descriptor */
      8'h09,  /* bLength = 9 */
      /* Configuration Descriptor */
      8'h32,  /* bMaxPower = 100 mA */
      8'hC0,  /* bmAttributes = Self-powered */
      8'h00,  /* iConfiguration */
      8'h01,  /* bConfigurationValue */
      8'h01,  /* bNumInterfaces = 1 */
      16'h0012,  /* wTotalLength = 18 */
      8'h02,  /* bDescriptionType = Configuration Descriptor */
      8'h09  /* bLength = 9 */
    },
    parameter integer HIGH_SPEED = 1
) (
    input reset,
    input clock,

    input  select_i,
    input  start_i,
    input  stop_i,
    output error_o,

    output configured_o,
    output [6:0] usb_addr_o,
    output [7:0] usb_conf_o,

    input [ 3:0] req_endpt_i,
    input [ 7:0] req_type_i,
    input [ 7:0] req_args_i,
    input [15:0] req_value_i,
    input [15:0] req_index_i,
    input [15:0] req_length_i,

    // AXI4-Stream for device descriptors
    output m_tvalid_o,
    input m_tready_i,
    output m_tlast_o,
    output [7:0] m_tdata_o
);

  function [(2+2*MANUFACTURER_LEN)*8-1:0] desc_manufacturer;
    input [MANUFACTURER_LEN*8-1:0] str;
    integer i;
    begin
      desc_manufacturer[8*(0+1)-1-:8] = 2 + 2 * MANUFACTURER_LEN;
      desc_manufacturer[8*(1+1)-1-:8] = 8'h03;
      for (i = 0; i < MANUFACTURER_LEN; i = i + 1) begin
        desc_manufacturer[8*(2+2*i+1)-1-:8] = str[8*(MANUFACTURER_LEN-i)-1-:8];
        desc_manufacturer[8*(3+2*i+1)-1-:8] = 8'h00;
      end
    end
  endfunction

  function [(2+2*PRODUCT_LEN)*8-1:0] desc_product;
    input [PRODUCT_LEN*8-1:0] str;
    integer i;
    begin
      desc_product[8*(0+1)-1-:8] = 2 + 2 * PRODUCT_LEN;
      desc_product[8*(1+1)-1-:8] = 8'h03;
      for (i = 0; i < PRODUCT_LEN; i = i + 1) begin
        desc_product[8*(2+2*i+1)-1-:8] = str[8*(PRODUCT_LEN-i)-1-:8];
        desc_product[8*(3+2*i+1)-1-:8] = 8'h00;
      end
    end
  endfunction

  function [(2+2*SERIAL_LEN)*8-1:0] desc_serial;
    input [SERIAL_LEN*8-1:0] str;
    integer i;
    begin
      desc_serial[8*(0+1)-1-:8] = 2 + 2 * SERIAL_LEN;
      desc_serial[8*(1+1)-1-:8] = 8'h03;
      for (i = 0; i < SERIAL_LEN; i = i + 1) begin
        desc_serial[8*(2+2*i+1)-1-:8] = str[8*(SERIAL_LEN-i)-1-:8];
        desc_serial[8*(3+2*i+1)-1-:8] = 8'h00;
      end
    end
  endfunction

  /* Full Speed Descriptor */
  localparam [18*8-1:0] DEVICE_DESC_FS = {
    8'h01,  /* bNumConfigurations = 1 */
    (SERIAL_LEN == 0 ? 8'h00 : 8'h03),  /* iSerialNumber */
    (PRODUCT_LEN == 0 ? 8'h00 : 8'h02),  /* iProduct */
    (MANUFACTURER_LEN == 0 ? 8'h00 : 8'h01),  /* iManufacturer */
    16'h0000,  /* bcdDevice */
    PRODUCT_ID,  /* idProduct */
    VENDOR_ID,  /* idVendor */
    8'h40,  /* bMaxPacketSize = 64 */
    8'h00,  /* bDeviceProtocol */
    8'h00,  /* bDeviceSubClass */
    8'hFF,  /* bDeviceClass = None */
    16'h0110,  /* bcdUSB = USB 1.1 */
    8'h01,  /* bDescriptionType = Device Descriptor */
    8'h12  /* bLength = 18 */
  };

  /* High Speed Descriptor */
  localparam [18*8-1:0] DEVICE_DESC_HS = {
    8'h01,  /* bNumConfigurations = 1 */
    (SERIAL_LEN == 0 ? 8'h00 : 8'h03),  /* iSerialNumber */
    (PRODUCT_LEN == 0 ? 8'h00 : 8'h02),  /* iProduct */
    (MANUFACTURER_LEN == 0 ? 8'h00 : 8'h01),  /* iManufacturer */
    16'h0000,  /* bcdDevice */
    PRODUCT_ID,  /* idProduct */
    VENDOR_ID,  /* idVendor */
    8'h40,  /* bMaxPacketSize = 64 */
    8'h00,  /* bDeviceProtocol */
    8'h00,  /* bDeviceSubClass */
    8'hFF,  /* bDeviceClass = None */
    16'h0200,  /* bcdUSB = USB 2.0 */
    8'h01,  /* bDescriptionType = Device Descriptor */
    8'h12  /* bLength = 18 */
  };

  localparam [18*8-1:0] DEVICE_DESC = (HIGH_SPEED) ? {DEVICE_DESC_HS} : {DEVICE_DESC_FS};

  localparam [4*8-1:0] STR_DESC = {
    16'h0409,
    8'h03,  /* bDescriptorType = String Descriptor */
    8'h04  /* bLength = 4 */
  };

  localparam [MANUFACTURER_LEN*16+15:0] MANUFACTURER_STR_DESC = desc_manufacturer(MANUFACTURER);
  localparam [PRODUCT_LEN*16+15:0] PRODUCT_STR_DESC = desc_product(PRODUCT);
  localparam [SERIAL_LEN*16+15:0] SERIAL_STR_DESC = desc_serial(SERIAL);

  localparam integer DEVICE_DESC_LEN = 18;
  localparam integer STR_DESC_LEN = 4;
  localparam integer MANUFACTURER_STR_DESC_LEN = 2 + 2 * MANUFACTURER_LEN;
  localparam integer PRODUCT_STR_DESC_LEN = 2 + 2 * PRODUCT_LEN;
  localparam integer SERIAL_STR_DESC_LEN = 2 + 2 * SERIAL_LEN;

  localparam integer DESC_SIZE_NOSTR = DEVICE_DESC_LEN + CONFIG_DESC_LEN;
  localparam integer DESC_SIZE_STR   =
             DESC_SIZE_NOSTR + STR_DESC_LEN + MANUFACTURER_STR_DESC_LEN +
             PRODUCT_STR_DESC_LEN + SERIAL_STR_DESC_LEN;

  localparam DESC_HAS_STRINGS = MANUFACTURER_LEN > 0 || PRODUCT_LEN > 0 || SERIAL_LEN > 0 ? 1 : 0;

  localparam integer DESC_SIZE = (DESC_HAS_STRINGS == 1) ? {DESC_SIZE_STR} : {DESC_SIZE_NOSTR};
  localparam integer DSB = DESC_SIZE * 8 - 1;
  localparam [DSB:0] USB_DESC = (DESC_HAS_STRINGS == 1) ? {SERIAL_STR_DESC, PRODUCT_STR_DESC, MANUFACTURER_STR_DESC, STR_DESC, CONFIG_DESC, DEVICE_DESC} : {CONFIG_DESC, DEVICE_DESC};

  localparam integer DESC_ROM_SIZE = 1 << $clog2(DESC_SIZE + 1);
  localparam integer ABITS = $clog2(DESC_SIZE + 1);
  localparam integer ASB = ABITS - 1;

  localparam [ASB:0] DESC_CONFIG_START = DEVICE_DESC_LEN;
  localparam [ASB:0] DESC_STRING_START = DEVICE_DESC_LEN + CONFIG_DESC_LEN;

  localparam [ASB:0] DESC_START0 = DESC_STRING_START;
  localparam [ASB:0] DESC_START1 = DESC_START0 + STR_DESC_LEN;
  localparam [ASB:0] DESC_START2 = DESC_START1 + MANUFACTURER_STR_DESC_LEN;
  localparam [ASB:0] DESC_START3 = DESC_START2 + PRODUCT_STR_DESC_LEN;

  localparam [ASB:0] DESC_END0 = DESC_CONFIG_START - 1;
  localparam [ASB:0] DESC_END1 = DESC_STRING_START - 1;
  localparam [ASB:0] DESC_END2 = DESC_START1 - 1;
  localparam [ASB:0] DESC_END3 = DESC_START2 - 1;
  localparam [ASB:0] DESC_END4 = DESC_START3 - 1;
  localparam [ASB:0] DESC_END5 = DESC_START3 + SERIAL_STR_DESC_LEN - 1;


  // -- Current USB Configuration State -- //

  reg [6:0] adr_q = 7'h00;
  reg [7:0] cfg_q = 8'h00;
  reg set_q = 1'b0;


  // -- Local Control-Transfer State and Signals -- //

  reg err_q, get_desc_q;
  reg [ASB:0] mem_addr;
  wire [ASB:0] mem_next;


  // -- Descriptor ROM -- //

  reg [7:0] descriptor[0:DESC_ROM_SIZE-1];
  reg desc_tlast[0:DESC_ROM_SIZE-1];

  genvar ii;
  generate

    for (ii = 0; ii < DESC_ROM_SIZE; ii++) begin : g_set_descriptor_rom
      assign descriptor[ii] = ii < DESC_SIZE ? USB_DESC[ii*8+7:ii*8] : ii;
      assign desc_tlast[ii] = ii==DESC_END0 || ii==DESC_END1 || ii==DESC_END2 ||
                              ii==DESC_END3 || ii==DESC_END4 || ii==DESC_END5 ;
    end

  endgenerate


  // -- Signal Output Assignments -- //

  assign error_o = err_q;
  assign usb_addr_o = adr_q;
  assign usb_conf_o = cfg_q;
  assign configured_o = set_q;

  // AXI4-Stream master port for descriptor values
  assign m_tvalid_o = get_desc_q;
  assign m_tdata_o = descriptor[mem_addr];
  assign m_tlast_o = desc_tlast[mem_addr];


  // -- Pipelined Configuration-Request Decoder -- //

  reg sel_q, set_addr_q, set_conf_q;

  // Pipelined configuration-request decoder
  always @(posedge clock) begin
    sel_q <= req_type_i[6:0] == {2'b00, 5'b00000} && req_endpt_i == 4'h0;

    // Only be fussy on writes
    set_addr_q <= select_i && start_i && sel_q && req_args_i == 8'h05;
    set_conf_q <= select_i && start_i && sel_q && req_args_i == 8'h09;
  end


  // -- Error & Status Flags -- //

  always @(posedge clock) begin
    if (select_i && start_i && sel_q) begin
      err_q <= ~get_desc_q | ~set_addr_q | ~set_conf_q;
    end else if (!select_i) begin
      err_q <= 1'b0;
    end
  end


  // -- Configuration Control PIPE0 Logic -- //

  assign mem_next = mem_addr + 1;

  always @(posedge clock) begin
    if (select_i && start_i) begin
      if (req_value_i[9:8] == 2'h2) begin
        mem_addr <= DESC_CONFIG_START;
      end else if (req_value_i[9:8] == 2'h3 && DESC_HAS_STRINGS) begin
        case (req_value_i[1:0])
          2'd0: mem_addr <= DESC_START0;
          2'd1: mem_addr <= DESC_START1;
          2'd2: mem_addr <= DESC_START2;
          default: mem_addr <= DESC_START3;
        endcase
      end else begin
        mem_addr <= 0;
      end
    end else if (m_tready_i && get_desc_q) begin
      mem_addr <= mem_next;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      get_desc_q <= 1'b0;

      adr_q <= 7'd0;
      cfg_q <= 8'd0;
      set_q <= 1'b0;
    end else begin

      if (get_desc_q && m_tready_i) begin
        get_desc_q <= !(m_tlast_o || stop_i);
      end else if (start_i && select_i) begin
        get_desc_q <= req_args_i == 8'h06;
      end

      if (set_addr_q) begin
        adr_q <= req_value_i[6:0];
      end

      if (set_conf_q) begin
        set_q <= 1'b1;
        cfg_q <= req_value_i[7:0];
      end

    end
  end


  // -- Simulation Only -- //

`ifdef __icarus

  initial begin : i_cfg_info
    $display("Total descriptor size:         %3d (bytes)", DESC_SIZE);
    $display(" - Device descriptor length:   %3d (bytes)", DEVICE_DESC_LEN);
    $display(" - Config descriptor length:   %3d (bytes)", CONFIG_DESC_LEN);
    if (DESC_HAS_STRINGS) begin
      $display(" - String descriptor length:   %3d (bytes)", STR_DESC_LEN);
      $display(" - Manufacturer string length: %3d (bytes)", MANUFACTURER_STR_DESC_LEN);
      $display(" - Product string length:      %3d (bytes)", PRODUCT_STR_DESC_LEN);
      $display(" - Serial string length:       %3d (bytes)", SERIAL_STR_DESC_LEN);
    end
    $display("Control PIPE0 config ROM size: %3d (bytes)", DESC_ROM_SIZE);
    $display("Control PIPE0 address bits:    %3d (bits)", ABITS);
  end

`endif


endmodule  // ctl_pipe0
