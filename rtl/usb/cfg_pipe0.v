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
module cfg_pipe0 #(
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
    input wire reset,
    input wire clock,

    input wire [ 3:0] ctl_xfer_endpoint,
    input wire [ 7:0] ctl_xfer_type,
    input wire [ 7:0] ctl_xfer_request,
    input wire [15:0] ctl_xfer_value,
    input wire [15:0] ctl_xfer_index,
    input wire [15:0] ctl_xfer_length,

    output wire ctl_xfer_gnt_o,
    input  wire ctl_xfer_req_i,

    output wire ctl_tvalid_o,
    input wire ctl_tready_i,
    output wire ctl_tlast_o,
    output wire [7:0] ctl_tdata_o,

    output wire [6:0] device_address,
    output wire [7:0] current_configuration,
    output wire configured,
    output wire standart_request
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
  localparam DEVICE_DESC_FS = {
    8'h01,  /* bNumConfigurations = 1 */
    (SERIAL_LEN == 0) ? 8'h00 : 8'h03,  /* iSerialNumber */
    (PRODUCT_LEN == 0) ? 8'h00 : 8'h02,  /* iProduct */
    (MANUFACTURER_LEN == 0) ? 8'h00 : 8'h01,  /* iManufacturer */
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
  localparam DEVICE_DESC_HS = {
    8'h01,  /* bNumConfigurations = 1 */
    (SERIAL_LEN == 0) ? 8'h00 : 8'h03,  /* iSerialNumber */
    (PRODUCT_LEN == 0) ? 8'h00 : 8'h02,  /* iProduct */
    (MANUFACTURER_LEN == 0) ? 8'h00 : 8'h01,  /* iManufacturer */
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

  localparam DEVICE_DESC = HIGH_SPEED ? DEVICE_DESC_HS : DEVICE_DESC_FS;

  localparam [4*8-1:0] STR_DESC = {
    16'h0409,
    8'h03,  /* bDescriptorType = String Descriptor */
    8'h04  /* bLength = 4 */
  };

  localparam MANUFACTURER_STR_DESC = desc_manufacturer(MANUFACTURER);
  localparam PRODUCT_STR_DESC = desc_product(PRODUCT);
  localparam SERIAL_STR_DESC = desc_serial(SERIAL);

  localparam DEVICE_DESC_LEN = 18;
  localparam STR_DESC_LEN = 4;
  localparam MANUFACTURER_STR_DESC_LEN = 2 + 2 * MANUFACTURER_LEN;
  localparam PRODUCT_STR_DESC_LEN = 2 + 2 * PRODUCT_LEN;
  localparam SERIAL_STR_DESC_LEN = 2 + 2 * SERIAL_LEN;

  localparam DESC_WITH_STRINGS = {
    SERIAL_STR_DESC, PRODUCT_STR_DESC, MANUFACTURER_STR_DESC, STR_DESC, CONFIG_DESC, DEVICE_DESC
  };

  localparam DESC_SIZE_NOSTR = DEVICE_DESC_LEN + CONFIG_DESC_LEN;
  localparam DESC_SIZE_STR   =
             DESC_SIZE_NOSTR + STR_DESC_LEN + MANUFACTURER_STR_DESC_LEN +
             PRODUCT_STR_DESC_LEN + SERIAL_STR_DESC_LEN;

  localparam DESC_HAS_STRINGS = MANUFACTURER_LEN > 0 || PRODUCT_LEN > 0 || SERIAL_LEN > 0;

  localparam DESC_SIZE = DESC_HAS_STRINGS ? DESC_SIZE_STR : DESC_SIZE_NOSTR;
  localparam USB_DESC = DESC_HAS_STRINGS ? DESC_WITH_STRINGS : {CONFIG_DESC, DEVICE_DESC};

  localparam DESC_CONFIG_START = DEVICE_DESC_LEN;
  localparam DESC_STRING_START = DEVICE_DESC_LEN + CONFIG_DESC_LEN;

  localparam DESC_START0 = DESC_STRING_START;
  localparam DESC_START1 = DESC_START0 + STR_DESC_LEN;
  localparam DESC_START2 = DESC_START1 + MANUFACTURER_STR_DESC_LEN;
  localparam DESC_START3 = DESC_START2 + PRODUCT_STR_DESC_LEN;

  // -- Current USB Configuration State -- //

  reg [6:0] adr_q;
  reg [7:0] cfg_q;
  reg set_q;


  // -- Local State and Signals -- //

  localparam [2:0]
	STATE_IDLE = 3'd0,
	STATE_GET_DESC = 3'd1,
	STATE_SET_CONF = 3'd2,
	STATE_SET_ADDR = 3'd4;

  localparam ASB = $clog2(DESC_SIZE) - 1;

  reg [2:0] state;
  reg gnt_q;
  reg [ASB:0] mem_addr;
  wire [ASB:0] mem_next;

  wire is_std_req;
  wire is_dev_req;
  wire handle_req;

  /**
   * Request types:
   *	000 - None
   *	001 - Get device descriptor
   *	010 - Set address
   *	011 - Get configuration descriptor
   *	100 - Set configuration
   *	101 - Get string descriptor
   */
  reg [2:0] req_type;


  // -- Signal Output Assignments -- //

  assign device_address = adr_q;
  assign current_configuration = cfg_q;
  assign configured = set_q;

  // todo: make non-combinational ...
  assign standart_request = is_std_req;

  assign ctl_xfer_gnt_o = gnt_q;

  // AXI4-Stream master port for descriptor values
  assign ctl_tvalid_o = state[0];
  assign ctl_tdata_o = descriptor[mem_addr];
  assign ctl_tlast_o = desc_tlast[mem_addr];


  // -- Internal Combinational Assignments -- //

  assign is_std_req = ctl_xfer_endpoint == 4'h0 && ctl_xfer_type[6:5] == 2'b00;
  assign is_dev_req = ctl_xfer_type[4:0] == 5'b00000;
  assign handle_req = is_std_req & is_dev_req;

  // todo: can I improve this !?
  always @(*) begin
    if (handle_req && (ctl_xfer_request == 8'h06) && (ctl_xfer_value[15:8] == 8'h01)) begin
      req_type = 3'b001;
    end else if (handle_req && (ctl_xfer_request == 8'h05)) begin
      req_type = 3'b010;
    end else if (handle_req && (ctl_xfer_request == 8'h06) && (ctl_xfer_value[15:8] == 8'h02)) begin
      req_type = 3'b011;
    end else if (handle_req && (ctl_xfer_request == 8'h09)) begin
      req_type = 3'b100;
    end else if (handle_req && (ctl_xfer_request == 8'h06) && (ctl_xfer_value[15:8] == 8'h03)) begin
      req_type = 3'b101;
    end else begin
      req_type = 3'b000;
    end
  end


  // -- Descriptor ROM -- //

  reg [7:0] descriptor[0:DESC_SIZE-1];
  reg desc_tlast[0:DESC_SIZE-1];

  genvar ii;
  generate

    for (ii = 0; ii < DESC_SIZE; ii++) begin : g_set_descriptor_rom
      assign descriptor[ii] = USB_DESC[ii*8+7:ii*8];
      assign desc_tlast[ii] = ii==DESC_CONFIG_START-1 || ii==DESC_START0-1 ||
                            ii==DESC_START1-1 || ii==DESC_START2-1 ||
                            ii==DESC_START3-1 || ii==DESC_SIZE-1;
    end

  endgenerate


  // -- Configuration Control PIPE0 Logic -- //

  assign mem_next = mem_addr + 1;

  always @(posedge clock) begin
    if (ctl_xfer_req_i) begin
      gnt_q <= req_type != 3'b000;
    end else begin
      gnt_q <= 1'b0;
    end
  end

  always @(posedge clock) begin
    if (ctl_tready_i && state[0]) begin
      mem_addr <= mem_next;
    end else if (ctl_xfer_req_i && !state[0]) begin
      if (req_type == 3'b011) begin
        mem_addr <= DESC_CONFIG_START;
      end else if (DESC_HAS_STRINGS && (req_type == 3'b101)) begin
        if (ctl_xfer_value[7:0] == 8'h00) begin
          mem_addr <= DESC_START0;
        end else if (ctl_xfer_value[7:0] == 8'h01) begin
          mem_addr <= DESC_START1;
        end else if (ctl_xfer_value[7:0] == 8'h02) begin
          mem_addr <= DESC_START2;
        end else if (ctl_xfer_value[7:0] == 8'h03) begin
          mem_addr <= DESC_START3;
        end
      end else begin
        mem_addr <= 0;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      state <= STATE_IDLE;
      adr_q <= 0;
      set_q <= 1'b0;
    end else begin
      case (state)
        default: begin
          if (ctl_xfer_req_i) begin
            if ((req_type == 3'b001) || (req_type == 3'b011) || (req_type == 3'b101)) begin
              state <= STATE_GET_DESC;
            end else if (req_type == 3'b010) begin
              state <= STATE_SET_ADDR;
            end else if (req_type == 3'b100) begin
              cfg_q <= ctl_xfer_value[7:0];
              state <= STATE_SET_CONF;
            end
          end
        end
        STATE_SET_ADDR: begin
          if (!ctl_xfer_req_i) begin
            state <= STATE_IDLE;
            adr_q <= ctl_xfer_value[6:0];
          end
        end
        STATE_GET_DESC: begin
          if (!ctl_xfer_req_i) begin
            state <= STATE_IDLE;
          end
        end
        STATE_SET_CONF: begin
          if (!ctl_xfer_req_i) begin
            set_q <= 1'b1;
            state <= STATE_IDLE;
          end
        end
      endcase
    end
  end


endmodule  // cfg_pipe0
