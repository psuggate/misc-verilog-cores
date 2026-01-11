`timescale 1ns / 100ps
module mmio_ep_out_tb;

  `define CMD_STORE 4'h0

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
  wire [7:0] s_tdata, tdata_w;

  always #8 clock <= ~clock;

  reg [7:0] len_q = 8'd7;
  reg [3:0] lun_q = 4'd0, tag_q = 4'hA;
  reg [27:0] adr_q = 28'h0800;

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

    axi_send(len_q, tag_q, adr_q, lun_q);

    #800 $finish;
  end

  initial begin : FAIL_SAFE
    #2560 $finish;
  end

  mmio_ep_out U_EPOUT0 (
      .clock(clock),
      .reset(reset),

      .set_conf_i(ep_set_q),  // From CONTROL PIPE0
      .clr_conf_i(ep_clr_q),  // From CONTROL PIPE0
      .max_size_i(10'd64),    // From CONTROL PIPE0

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


  //
  //  Simulation tasks for entire transactions.
  //
  integer lim_q;
  reg [10:0] cnt_q;
  reg [7:0] rnd_q;
  reg [87:0] req_q;
  wire [11:0] inc_w;

  assign s_tdata = req_q[7:0];
  assign inc_w   = cnt_q + 1;

  /**
   * Send a command frame, followed by as many data frames as required.
   */
  task axi_send;
    input [7:0] size;
    input [3:0] tag;
    input [27:0] addr;
    input [3:0] lun;
    begin
      // Select the OUT EP.
      @(posedge clock);
      s_tvalid <= #2 1'b0;
      s_tkeep <= #2 1'b0;
      s_tlast <= #2 1'b0;
      lim_q <= #2{24'd0, size};
      sel_q <= #2 1'b1;

      @(negedge clock) #16 $display("%11t: Starting AXI STORE", $time);

      @(posedge clock) begin
        s_tvalid <= #2 1'b1;
        s_tkeep <= #2 1'b1;
        s_tlast <= #2 1'b0;
        cnt_q <= #2 s_tvalid && tready_w ? 11'd1 : 11'd0;
        req_q <= #2{tag, `CMD_STORE, 8'd0, size, lun, addr, "T", "R", "A", "T"};
        rnd_q <= $urandom;
      end

      @(negedge clock) $display("%11t: Sending AXI STORE (ADDR: %7x)", $time, addr);

      while (cnt_q < 11'd10) begin
        @(posedge clock);
        if (tready_w) begin
          cnt_q   <= #2 inc_w[10:0];
          req_q   <= #2{rnd_q, req_q[87:8]};
          rnd_q   <= #2 $urandom;
          s_tlast <= #2 inc_w < 12'd10 ? 1'b0 : 1'b1;
        end
        @(negedge clock);
      end

      @(posedge clock);
      s_tvalid <= #2 1'b0;
      s_tkeep <= #2 1'b0;
      s_tlast <= #2 1'b0;
      req_q <= #2{rnd_q, req_q[87:8]};

      // Todo: the target device is supposed to 'ACK' the command frame.
      @(negedge clock) #32 $display("%11t: Sending USB ACK", $time);
      @(posedge clock) ack_q <= #2 1'b1;
      #16 ack_q <= #2 1'b0;

      @(posedge clock) #32 sel_q <= #2 1'b0;
      #32 sel_q <= #2 1'b1;

      // Send the requested number of bytes.
      $display("%11t: Sending AXI STORE (DATA: %d)", $time, cnt_q);
      #16 cnt_q <= 11'd0;

      @(posedge clock) begin
        s_tvalid <= #2 1'b1;
        s_tkeep <= #2 1'b1;
        s_tlast <= #2 size == 8'd0 ? 1'b1 : 1'b0;
        cnt_q <= #2 s_tvalid && tready_w ? 11'd1 : 11'd0;
      end

      while (!(cnt_q == lim_q[10:0] && tready_w)) begin
        @(posedge clock);
        if (tready_w) begin
          cnt_q   <= #2 inc_w[10:0];
          req_q   <= #2{rnd_q, req_q[87:8]};
          rnd_q   <= #2 $urandom;
          s_tlast <= #2 inc_w < lim_q[11:0] ? 1'b0 : 1'b1;
        end
        @(negedge clock);
      end

      $display("%11t: Finishing AXI STORE", $time);
      @(posedge clock);
      s_tvalid <= #2 1'b0;
      s_tkeep  <= #2 1'b0;
      s_tlast  <= #2 1'b0;

      // Todo: the target device is supposed to 'ACK' the command frame.
      @(negedge clock) #64 $display("%11t: Sending USB ACK", $time);
      @(posedge clock) ack_q <= #2 1'b1;
      #16 ack_q <= #2 1'b0;

      @(negedge clock) #16 $display("%11t: Finished AXI STORE", $time);
      @(posedge clock) sel_q <= #2 1'b0;
      #48 resp_q <= #2 1'b1;
      #16 resp_q <= #2 1'b0;

    end
  endtask  /* axi_send */

`ifdef __potatoe

  task ddr_recv;
    input [7:0] size;
    input [27:0] addr;
    begin
      @(negedge clock) $display("%11t: Starting DDR3 FETCH\n", $time);

      @(posedge clock) begin
        s_tvalid <= #2 1'b1;
        s_tkeep <= #2 1'b1;
        s_tlast <= #2 1'b0;
        cnt_q <= s_tvalid && tready_w ? 11'd1 : 11'd0;
        req_q <= #2{4'hA, addr, size, CMD_FETCH};
      end

      @(negedge clock) $display("%11t: Sending DDR3 FETCH (ADDR: %7x)\n", $time, addr);

      while (!(cnt_q == 11'd5 && tready_w)) begin
        @(posedge clock);
        if (tready_w) begin
          cnt_q   <= #2 inc_w[10:0];
          req_q   <= #2{8'bx, req_q[47:8]};
          s_tlast <= #2 cnt_q < 11'd4 ? 1'b0 : 1'b1;
        end
        @(negedge clock);
      end

      $display("%11t: Sent DDR3 FETCH\n", $time);
      @(posedge clock);
      s_tvalid <= #2 1'b0;
      s_tkeep  <= #2 1'b0;
      s_tlast  <= #2 1'b0;

      @(negedge clock) $display("%11t: Waiting for DDR3 FETCH\n", $time);

    end
  endtask  /* ddr_recv */

`endif  /* __potatoe */

endmodule  /* mmio_ep_out_tb */
