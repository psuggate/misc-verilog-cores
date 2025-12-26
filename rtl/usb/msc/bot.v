`timescale 1ns / 100ps
//
// USB Mass Storage Class (MSC) device using the Bulk-Only Transport (BOT)
// protocol.
//
// Note(s):
//  - (BOT) does not support command-queuing;
//  - minimal state-logic, just ensuring that a CSW is issued for each CBW;
//
module bot (
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

    input scsi_busy_i,
    input scsi_done_i,

    // SCSI command, and WRITE, stream
    output scsi_tvalid_o,
    input scsi_tready_i,
    output scsi_tlast_o,
    output [7:0] scsi_tdata_o,

    // SCSI command, and WRITE, stream
    input scsi_tvalid_i,
    output scsi_tready_o,
    input scsi_tlast_i,
    input [7:0] scsi_tdata_i
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
              .error_i(error_o),

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


endmodule  /* bot */
