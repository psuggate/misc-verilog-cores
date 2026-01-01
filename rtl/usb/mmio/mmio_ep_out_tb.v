`timescale 1ns / 100ps
module mmio_ep_out_tb;

  reg clock = 1;
  reg reset;

  reg busy_q, sent_q, resp_q, done_q;
  wire recv_w;

  reg ep_set_q, ep_clr_q;
  reg sel_q, err_q, ack_q;
  wire ep_ready_w, ep_stall_w, ep_out_par;

  reg cmd_ack_q;
  wire cmd_vld_w, cmd_dir_w, cmd_apb_w;
  wire [1:0] cmd_cmd_w;
  wire [3:0] cmd_lun_w, cmd_tag_w;
  wire [15:0] cmd_len_w;
  wire [27:0] cmd_adr_w;

  reg s_tvalid, s_tkeep, s_tlast, m_tready;
  wire tvalid_w, tready_w, tkeep_w, tlast_w;
  reg [7:0] s_tdata;
  wire [7:0] tdata_w;

  always #8 clock <= ~clock;

  initial begin : SIM_FTW
    $dumpfile("mmio_ep_out_tb.vcd");
    $dumpvars;

    #2 reset <= 1'b1;
    {ep_set_q, ep_clr_q} <= 2'b0;
    {sel_q, err_q, ack_q} <= 3'b0;
    {busy_q, sent_q, resp_q, done_q} <= 4'b0;
    cmd_ack_q <= 1'b0;
    {s_tvalid, s_tkeep, s_tlast} <= 3'b0;
    m_tready <= 1'b0;

    #160 reset <= 1'b0;

    #80 ep_set_q <= 1'b1;
    #16 ep_set_q <= 1'b0;

    #2000 $finish;
  end


  mmio_ep_out U_EPOUT0 (
      .clock(clock),
      .reset(reset),

      .set_conf_i(ep_set_q),  // From CONTROL PIPE0
      .clr_conf_i(ep_clr_q),  // From CONTROL PIPE0
      .max_size_i(9'd64),  // From CONTROL PIPE0

      .selected_i(sel_q),  // From USB controller
      .rx_error_i(err_q),  // Timed-out or CRC16 error
      .ack_sent_i(ack_q),

      .ep_ready_o(ep_ready_w),
      .stalled_o (ep_stall_w),  // If invariants violated
      .parity_o  (ep_out_par),

      // From MMIO controller
      .mmio_busy_i(busy_q),  // Todo: what do I want?
      .mmio_recv_o(recv_w),
      .mmio_sent_i(sent_q),
      .mmio_resp_i(resp_q),
      .mmio_done_i(done_q),

      // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
      .usb_tvalid_i(s_tvalid),
      .usb_tready_o(tready_w),
      .usb_tkeep_i (s_tkeep),
      .usb_tlast_i (s_tlast),
      .usb_tdata_i (s_tdata),

      // Decoded command (APB, or AXI)
      .cmd_vld_o(cmd_vld_w),
      .cmd_ack_i(cmd_ack_q),
      .cmd_dir_o(cmd_dir_w),
      .cmd_apb_o(cmd_apb_w),
      .cmd_cmd_o(cmd_cmd_w),
      .cmd_tag_o(cmd_tag_w),
      .cmd_len_o(cmd_len_w),
      .cmd_lun_o(cmd_lun_w),
      .cmd_adr_o(cmd_adr_w),

      // Pass-through data stream, from USB (Bulk-Out, via AXI-S)
      .dat_tvalid_o(tvalid_w),
      .dat_tready_i(m_tready),
      .dat_tlast_o (tlast_w),
      .dat_tdata_o (tdata_w)
  );


endmodule  /* mmio_ep_out_tb */
