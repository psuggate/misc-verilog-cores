`timescale 1ns / 100ps
//
// Parser for USB Bulk-Only Transport (BOT) Command Block Wrapper (CBW) frames.
//
module csw (
    input clock,
    input reset,

    input  enable_i,
    input error_i,

    // From SCSI controller
    input scsi_done_i,

    // Decoded CBW (Command Block Wrapper)
    input cbw_vld_i,
    input cbw_dir_i,
    input [31:0] cbw_tag_i,
    input [31:0] cbw_len_i,

    // USB status, and READ, packet stream (Bulk-Out pipe, AXI-S)
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tlast_o,
    output [7:0] usb_tdata_o
);



  axis_skid #(
      .WIDTH (8),
      .BYPASS(0)
  ) U_SKID0 (
      .clock(clock),
      .reset(enb),

      .s_tvalid(usb_tvalid_i),
      .s_tready(skid_ready_w),
      .s_tlast (usb_tlast_i),
      .s_tdata (usb_tdata_i),

      .m_tvalid(cb_tvalid_o),
      .m_tready(cb_tready_i),
      .m_tlast (cb_tlast_o),
      .m_tdata (cb_tdata_o)
  );


endmodule  /* cbw */
