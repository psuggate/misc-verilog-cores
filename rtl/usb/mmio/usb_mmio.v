`timescale 1ns / 100ps
//
// USB to Memory-Mapped IO (via AXI4) logic core.
//
// Commands:
//  - GET/SET APB transactions;
//  - FETCH/STORE AXI transfers;
//  - READY query;
//  - QUERY for device information;
//
// Note(s):
//  - (MMIO) does not support command-queuing;
//  - minimal state-logic, just ensuring that a response is issued after each
//    command (and its corresponding data phase, if present);
//
module usb_mmio (
    input clock,
    input reset,

    input  enable_i,
    output error_o,

    // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // USB status, and READ, packet stream (Bulk-Out pipe, AXI-S)
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output [7:0] usb_tdata_o,

    // APB requester interface, to controllers
    output penable_o,
    output pwrite_o,
    output pstrb_o,
    input pready_i,
    input pslverr_i,
    output [ASB:0] paddr_o,
    output [7:0] pwdata_o,
    input [7:0] prdata_i,

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

  reg cbw_ack_q;
  wire cbw_tvalid_w, cbw_tready_w, cbw_tlast_w;
  wire cb_tvalid_w, cb_tready_w, cb_tlast_w;
  wire cbw_vld_w, cbw_dir_w;
  wire [7:0] cbw_tdata_w, cb_tdata_w;
  wire [31:0] cbw_tag_w, cbw_len_w;
  wire [3:0] cbw_lun_w;


  cbw U_CBW0 (
      .clock(clock),
      .reset(reset),
      .enable_i(enable_i),
      .error_o(error_o),

      .scsi_busy_i(scsi_busy_i),
      .scsi_done_i(scsi_done_i),

      .usb_tvalid_i(cbw_tvalid_w),
      .usb_tready_o(cbw_tready_w),
      .usb_tlast_i (cbw_tlast_w),
      .usb_tdata_i (cbw_tdata_w),

      .cbw_vld_o(cbw_vld_w),
      .cbw_dir_o(cbw_dir_w),
      .cbw_ack_i(cbw_ack_q),
      .cbw_tag_o(cbw_tag_w),
      .cbw_len_o(cbw_len_w),
      .cbw_lun_o(cbw_lun_w),

      .cb_tvalid_o(cb_tvalid_w),
      .cb_tready_o(cb_tready_w),
      .cb_tlast_o (cb_tlast_w),
      .cb_tdata_o (cb_tdata_w)
  );


  csw U_CSW0 (
      .clock(clock),
      .reset(reset),

      .enable_i(enable_i),
      .error_i (error_o),

      .scsi_done_i(scsi_done_i),

      .cbw_vld_i(cbw_vld_w),
      .cbw_dir_i(cbw_dir_w),
      .cbw_tag_i(cbw_tag_w),
      .cbw_len_i(cbw_len_w),

      .usb_tvalid_o(usb_tvalid_o),
      .usb_tready_i(usb_tready_i),
      .usb_tlast_o (usb_tlast_o),
      .usb_tdata_o (usb_tdata_o)
  );


endmodule  /* usb_mmio */
