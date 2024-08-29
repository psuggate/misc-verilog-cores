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
    parameter integer MAX_CONFIG_LENGTH = 64,  // For HS- & FS- modes

    parameter [15:0] VENDOR_ID = 16'hFACE,
    parameter [15:0] PRODUCT_ID = 16'h0BDE,
    parameter MANUFACTURER_LEN = 0,
    parameter MANUFACTURER = "",
    parameter PRODUCT_LEN = 0,
    parameter PRODUCT = "",
    parameter SERIAL_LEN = 0,
    parameter SERIAL = "",

    parameter integer DEVICE_DESC_LEN = 18,
    parameter [143:0] DEVICE_DESC = {
      8'h01,  /* bNumConfigurations = 1 */
      (SERIAL_LEN == 0 ? 8'h00 : 8'h03),  /* iSerialNumber */
      (PRODUCT_LEN == 0 ? 8'h00 : 8'h02),  /* iProduct */
      (MANUFACTURER_LEN == 0 ? 8'h00 : 8'h01),  /* iManufacturer */
      16'h0000,  /* bcdDevice */
      PRODUCT_ID[15:0],  /* idProduct */
      VENDOR_ID[15:0],  /* idVendor */
      8'h40,  /* bMaxPacketSize = 64 */
      8'h00,  /* bDeviceProtocol */
      8'h00,  /* bDeviceSubClass */
      8'hFF,  /* bDeviceClass = None */
      16'h0200,  /* bcdUSB = USB 2.0 */
      8'h01,  /* bDescriptionType = Device Descriptor */
      8'h12  /* bLength = 18 */
    },

    parameter integer CONFIG_DESC_LEN = 18,
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
    }
) (
    input reset,
    input clock,

    input  select_i,
    input  status_i,
    input  start_i,
    output error_o,
    output event_o,

    output configured_o,
    output usb_enum_o,
    output [6:0] usb_addr_o,
    output [2:0] usb_conf_o,

    input [ 3:0] req_endpt_i,
    input [ 7:0] req_type_i,
    input [ 7:0] req_args_i,
    input [15:0] req_value_i,
    input [15:0] req_index_i,
    input [15:0] req_length_i,

    // AXI4-Stream for device descriptors
    output m_tvalid_o,
    input m_tready_i,
    output m_tkeep_o,
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

  localparam [4*8-1:0] STR_DESC = {
    16'h0409,
    8'h03,  /* bDescriptorType = String Descriptor */
    8'h04  /* bLength = 4 */
  };

  localparam [MANUFACTURER_LEN*16+15:0] MANUFACTURER_STR_DESC = desc_manufacturer(MANUFACTURER);
  localparam [PRODUCT_LEN*16+15:0] PRODUCT_STR_DESC = desc_product(PRODUCT);
  localparam [SERIAL_LEN*16+15:0] SERIAL_STR_DESC = desc_serial(SERIAL);

  localparam integer STR_DESC_LEN = 4;
  localparam integer MANUFACTURER_STR_DESC_LEN = 2 + 2 * MANUFACTURER_LEN;
  localparam integer PRODUCT_STR_DESC_LEN = 2 + 2 * PRODUCT_LEN;
  localparam integer SERIAL_STR_DESC_LEN = 2 + 2 * SERIAL_LEN;

  localparam integer DESC_SIZE_NOSTR = DEVICE_DESC_LEN + CONFIG_DESC_LEN + 6;
  localparam integer DESC_SIZE_STR   =
             DESC_SIZE_NOSTR + STR_DESC_LEN + MANUFACTURER_STR_DESC_LEN +
             PRODUCT_STR_DESC_LEN + SERIAL_STR_DESC_LEN;

  localparam DESC_HAS_STRINGS = MANUFACTURER_LEN > 0 || PRODUCT_LEN > 0 || SERIAL_LEN > 0 ? 1 : 0;

  // Complete descriptor size information //
  localparam integer DESC_SIZE = DESC_HAS_STRINGS == 1 ? DESC_SIZE_STR : DESC_SIZE_NOSTR;
  localparam integer DSB = DESC_SIZE * 8 - 1;
  localparam [DSB:0] USB_DESC = DESC_HAS_STRINGS == 1 ? {{16'h0, 16'h0, 16'h1}, SERIAL_STR_DESC, PRODUCT_STR_DESC, MANUFACTURER_STR_DESC, STR_DESC, CONFIG_DESC, DEVICE_DESC} : {{16'h0, 16'h0, 16'h1}, CONFIG_DESC, DEVICE_DESC};

  // Descriptor ROM parameters //
  localparam integer DESC_ROM_SIZE = 1 << $clog2(DESC_SIZE);
  localparam integer ABITS = $clog2(DESC_SIZE);
  localparam integer ASB = ABITS - 1;

  // Indices within the descriptor ROM //
  localparam integer DESC_CONFIG_START = DEVICE_DESC_LEN;
  localparam integer DESC_STRING_START = DEVICE_DESC_LEN + CONFIG_DESC_LEN;

  localparam integer DESC_START0 = DESC_STRING_START;
  localparam integer DESC_START1 = DESC_START0 + STR_DESC_LEN;
  localparam integer DESC_START2 = DESC_START1 + MANUFACTURER_STR_DESC_LEN;
  localparam integer DESC_START3 = DESC_START2 + PRODUCT_STR_DESC_LEN;

  localparam integer DESC_END0 = DEVICE_DESC_LEN - 1;
  localparam integer DESC_END1 = DESC_STRING_START - 1;
  localparam integer DESC_END2 = DESC_START1 - 1;
  localparam integer DESC_END3 = DESC_START2 - 1;
  localparam integer DESC_END4 = DESC_START3 - 1;
  localparam integer DESC_END5 = DESC_START3 + SERIAL_STR_DESC_LEN - 1;

  localparam integer DESC_STATUS_START = DESC_START3 + SERIAL_STR_DESC_LEN;
  localparam integer DESC_END6 = DESC_END5 + 2;
  localparam integer DESC_END7 = DESC_END5 + 4;
  localparam integer DESC_END8 = DESC_END5 + 6;


  // -- Current USB Configuration State -- //

  reg [6:0] adr_q = 7'h00;
  reg [7:0] cfg_q = 8'h00;
  reg enm_q = 1'b0, set_q = 1'b0;
  reg ctl_done_q;


  // -- Local Control-Transfer State and Signals -- //

  reg err_q, get_desc_q;
  reg [ASB:0] mem_addr;
  wire [ASB:0] mem_next;


  // -- Descriptor ROM -- //

  reg [7:0] descriptor[0:DESC_ROM_SIZE-1];
  // reg desc_tlast[0:DESC_ROM_SIZE-1];
  reg [DESC_ROM_SIZE-1:0] desc_tlast;

  integer ii;
  initial begin : g_init_rom
    for (ii = 0; ii < DESC_SIZE; ii++) begin : g_set_descriptor_rom
      descriptor[ii] = USB_DESC >> (ii * 8) & 8'hff;
      // desc_tlast[ii] = ii==DESC_END0 || ii==DESC_END1 || ii==DESC_END2 ||
      //                  ii==DESC_END3 || ii==DESC_END4 || ii==DESC_END5 ||
      //                  ii==DESC_END6 || ii==DESC_END7 || ii==DESC_END8 ;
    end
    desc_tlast = (1<<DESC_END0) | (1<<DESC_END1) | (1<<DESC_END2) |
                 (1<<DESC_END3) | (1<<DESC_END4) | (1<<DESC_END5) |
                 (1<<DESC_END6) | (1<<DESC_END7) | (1<<DESC_END8);
  end


  // -- Signal Output Assignments -- //

  assign error_o = err_q;
  assign event_o = ctl_done_q;

  assign usb_enum_o = enm_q;
  assign usb_addr_o = adr_q;
  assign usb_conf_o = cfg_q;
  assign configured_o = set_q;

  localparam MAXLEN = MAX_CONFIG_LENGTH;
  localparam MBITS = $clog2(MAXLEN + 1);
  localparam MSB = MBITS - 1;
  localparam MZERO = {MBITS{1'b0}};
  localparam MUNIT = {{MSB{1'b0}}, 1'b1};

  //
  // Burst-Chopper for Descriptor Data
  ///

  reg  [MSB:0] count;
  wire [MSB:0] cnext;

  wire tvalid_w, tready_w, tkeep_w, tlast_w;
  wire [7:0] tdata_w;

  assign cnext = count - 1;

  assign tvalid_w = status_i | (get_desc_q & ~count[6]);
  assign tkeep_w = ~status_i;
  assign tlast_w = status_i | desc_tlast[mem_addr] | cnext[6];
  assign tdata_w = descriptor[mem_addr];

  wire [MBITS:0] maxlen_w = (req_length_i > MAXLEN ? MAXLEN : req_length_i) - 1;

  always @(posedge clock) begin
    if (!select_i) begin
      count <= maxlen_w[6:0];
    end else if (tvalid_w && tready_w) begin
      count <= cnext[6:0];
    end
  end

  axis_skid #(
      .WIDTH (9),
      .BYPASS(0)
  ) U_SKID1 (
      .clock(clock),
      .reset(reset),

      .s_tvalid(tvalid_w),
      .s_tready(tready_w),
      .s_tlast (tlast_w),
      .s_tdata ({tkeep_w, tdata_w}),

      .m_tvalid(m_tvalid_o),
      .m_tready(m_tready_i),
      .m_tlast (m_tlast_o),
      .m_tdata ({m_tkeep_o, m_tdata_o})
  );

  //
  //  Process Control-Pipe Request
  ///

  // -- Pipelined Configuration-Request Decoder -- //

  reg std_req, start_q, set_addr_q, set_conf_q, set_face_q;

  // Pipelined configuration-request decoder
  always @(posedge clock) begin
    std_req <= req_type_i[6:0] == {2'b00, 5'b00000} && req_endpt_i == 4'h0;
    start_q <= start_i;

    // Only be fussy on writes
    if (select_i && start_i && std_req) begin
      set_addr_q <= req_args_i == 8'h05;
      set_conf_q <= req_args_i == 8'h09;
      set_face_q <= req_args_i == 8'h0b;
    end else begin
      set_addr_q <= 1'b0;
      set_conf_q <= 1'b0;
      set_face_q <= 1'b0;
    end
  end

  // -- Error & Status Flags -- //

  always @(posedge clock) begin
    if (select_i && start_q && std_req) begin
      err_q <= ~get_desc_q & ~set_addr_q & ~set_conf_q & ~set_face_q;
    end else if (!select_i) begin
      err_q <= 1'b0;
    end
  end

  // -- Read Address for Fetching Descriptors -- //

  localparam integer DESC_STATUS0_INDEX = DESC_STATUS_START;
  localparam integer DESC_STATUS1_INDEX = DESC_STATUS_START + 2;
  localparam integer DESC_STATUS2_INDEX = DESC_STATUS_START + 4;

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
      end else if (req_args_i[7:0] == 8'd0) begin
        case (req_type_i[1:0])
          2'd0: mem_addr <= DESC_STATUS0_INDEX;
          2'd1: mem_addr <= DESC_STATUS1_INDEX;
          2'd2: mem_addr <= DESC_STATUS2_INDEX;
          default: mem_addr <= 0;
        endcase
      end else begin
        mem_addr <= 0;
      end
    end else if (tready_w && get_desc_q) begin
      mem_addr <= mem_next;
    end
  end

  // -- Configuration & Control PIPE0 State Registers -- //

  always @(posedge clock) begin
    if (reset) begin
      get_desc_q <= 1'b0;
      ctl_done_q <= 1'b0;

      adr_q <= 7'd0;
      enm_q <= 1'b0;
      cfg_q <= 3'd0;
      set_q <= 1'b0;
    end else begin

      if (get_desc_q && tready_w) begin
        get_desc_q <= ~tlast_w;
      end else if (start_i && select_i && req_endpt_i == 4'h0) begin
        get_desc_q <= req_args_i == 8'h06 || req_args_i == 8'd0;
      end

      if (set_addr_q) begin
        enm_q <= 1'b1;
        adr_q <= req_value_i[6:0];
      end

      if (set_conf_q) begin
        set_q <= 1'b1;
        cfg_q <= req_value_i[2:0];
      end

      if (select_i && (set_addr_q || set_conf_q || set_face_q)) begin
        ctl_done_q <= 1'b1;
      end else
      if (select_i && status_i) begin

      end else begin
        ctl_done_q <= 1'b0;
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

`endif  /* __icarus */

endmodule  /* ctl_pipe0 */
