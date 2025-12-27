`timescale 1ns / 100ps
//
// Decode (AXI-S) streamed CBs, upto 16B in size, and generate SCSI commands.
//
module sbc
  ( input clock,
    input reset,

    input enable_i,
    output active_o,

    output scsi_busy_o,
    output scsi_done_o,
    output scsi_fail_o,

    // Parameters from the (USB) Command Block Wrapper (CBW)
    input cbw_vld_i,
    input cbw_dir_i,
    output cbw_ack_o,
    input [31:0] cbw_len_i,
    input [3:0] cbw_lun_i,

    // Command Block (CB) within wrapper (up to 16B in size), or Bulk-Out data
    // from USB host.
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // Data from target device to the USB host (Bulk-Out pipe, AXI-S)
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output [7:0] usb_tdata_o,

    // Memory-Controller AXI4 Interface
    output axi_awvalid_o,
    input axi_awready_i,
    output [ASB:0] axi_awaddr_o,
    output [ISB:0] axi_awid_o,
    output [7:0] axi_awlen_o,
    output [1:0] axi_awburst_o,

    output axi_wvalid_o,
    input axi_wready_i,
    output axi_wlast_o,
    output [SSB:0] axi_wstrb_o,
    output [MSB:0] axi_wdata_o,

    input axi_bvalid_i,
    output axi_bready_o,
    input [1:0] axi_bresp_i,
    input [ISB:0] axi_bid_i,

    output axi_arvalid_o,
    input axi_arready_i,
    output [ASB:0] axi_araddr_o,
    output [ISB:0] axi_arid_o,
    output [7:0] axi_arlen_o,
    output [1:0] axi_arburst_o,

    input axi_rvalid_i,
    output axi_rready_o,
    input axi_rlast_i,
    input [1:0] axi_rresp_i,
    input [ISB:0] axi_rid_i,
    input [MSB:0] axi_rdata_i
    );

`define PREVENT_ALLOW_MEDIUM_REMOVAL

`define TEST_UNIT_READY                         8'h00
`define REQUEST_SENSE                           8'h03
`define INQUIRY                                 8'h12
`define START_STOP_UNIT                         8'h1B

`define READ_6                                  8'h08
`define WRITE_6                                 8'h0A
`define MODE_SELECT_6                           8'h15
`define MODE_SENSE_6                            8'h1A

`define MODE_SELECT_10                          8'h55
`define MODE_SENSE_10                           8'h5A
`define READ_CAPACITY_10                        8'h25
`define READ_10                                 8'h28
`define WRITE_10                                8'h2A
`define WRITE_AND_VERIFY_10                     8'h2E
`define VERIFY_10                               8'h2F
`define SYNCHRONIZE_CACHE_10                    8'h35

`define READ_12                                 8'hA8
`define READ_16                                 8'h88
`define WRITE_12                                8'hAA
`define WRITE_16                                8'h8A
`define SYNCHRONIZE_CACHE_16                    8'h91

  localparam [3:0] ST_IDLE = 4'h0, ST_DECO = 4'h1, ST_READ = 4'h2, ST_WRIT = 4'h3;
  reg [3:0] state;

  always @* begin
    snext = ST_IDLE;
    case (usb_tdata_i)
      8'h28: snext = ST_RD_6;
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
    end
    else begin
      case (state)
        ST_IDLE: begin
          if (usb_tvalid_i && usb_tready_o) begin
            state <= snext;
          end
        end

        default: begin
          $fatal("Bad");
        end
      endcase
    end
  end


endmodule  /* sbc */
