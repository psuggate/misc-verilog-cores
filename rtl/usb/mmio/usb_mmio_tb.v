`timescale 1ns / 100ps
module usb_mmio_tb;

  `define CMD_STORE 4'h0
  `define CMD_FETCH 4'h8
  `define CMD_SET 4'h4
  `define CMD_GET 4'hC

  `include "axi_defs.vh"

  localparam FIFO_DEPTH = 512;
  localparam DATA_WIDTH = 32;
  localparam MSB = DATA_WIDTH - 1;

  localparam [7:0] CMD_NOP = 8'h00;
  localparam [7:0] CMD_READY = 8'h00;
  localparam [7:0] CMD_STORE = 8'h01;
  localparam [7:0] CMD_FETCH = 8'h80;
  localparam [7:0] CMD_QUERY = 8'hC0;

  localparam [7:0] RES_READY = 8'h00;
  localparam [7:0] RES_ERROR = 8'hFF;
  // localparam [7:0] CMD_STORE = 8'h01;
  localparam [7:0] RES_WDONE = 8'h02;
  localparam [7:0] RES_WFAIL = 8'h03;
  // localparam [7:0] CMD_FETCH = 8'h80;
  localparam [7:0] RES_RDATA = 8'h81;
  localparam [7:0] RES_RFAIL = 8'h82;

  reg clock = 1;
  reg reset;

  reg set_conf_q, clr_conf_q;
  reg ack_sent_q, ack_recv_q;
  reg timeout_q, epo_err_q;
  reg epo_sel_q, epi_sel_q, err_q;
  wire ep_ready_w, ep_stall_w, ep_out_par;

  reg cmd_ack_q;
  wire cmd_vld_w, cmd_dir_w, cmd_apb_w;
  wire [1:0] cmd_cmd_w;
  wire [3:0] cmd_lun_w, cmd_tag_w;
  wire [15:0] cmd_len_w;
  wire [27:0] cmd_adr_w;

  reg s_tvalid, s_tkeep, s_tlast, m_tready;
  wire s_tready, m_tvalid, m_tkeep, m_tlast;
  wire tvalid_w, tready_w, tkeep_w, tlast_w;
  wire [7:0] s_tdata, m_tdata, tdata_w;

  reg zdp_q;
  reg [7:0] len_q = 8'd7;
  reg [3:0] lun_q = 4'd0, tag_q = 4'hA;
  reg [27:0] adr_q = 28'h0800;

  reg mclk = 1, pclk = 1;
  reg presetn;
  wire areset_n, configured;

  reg [63:0] dbg_op;

  assign areset_n = ~reset;

  always #5 mclk <= ~mclk;
  always #8 clock <= ~clock;
  always #15 pclk <= ~pclk;

  always @(posedge pclk) begin
    presetn <= areset_n;
  end

  initial begin : SIM_FTW
    $dumpfile("usb_mmio_tb.vcd");
    $dumpvars;

    #2 reset <= 1'b1;
    dbg_op <= "RESET";
    {set_conf_q, clr_conf_q} <= 2'b0;
    {epo_sel_q, epi_sel_q, err_q, ack_sent_q, ack_recv_q} <= 5'b0;
    {cmd_ack_q, timeout_q, epo_err_q} <= 1'b0;
    {s_tvalid, s_tkeep, s_tlast} <= 3'b0;
    m_tready <= 1'b0;

    #160 reset <= 1'b0;
    dbg_op <= "IDLE";

    #80 set_conf_q <= 1'b1;
    dbg_op <= "USB_CONF";
    #16 set_conf_q <= 1'b0;
    dbg_op <= "IDLE";

    #16 dbg_op <= "APB_SEND";
    apb_send(16'hFACE, tag_q, adr_q, lun_q);
    dbg_op <= "IDLE";
    #64 dbg_op <= "APB_RECV";
    apb_recv(tag_q, adr_q, lun_q);
    dbg_op <= "IDLE";

    #64 dbg_op <= "AXI_SEND";
    axi_send(8'd7, tag_q, adr_q, lun_q);
    dbg_op <= "IDLE";

    #800 $finish;
  end

  initial begin : FAIL_SAFE
    #5120 $finish;
  end

  // -- Simulation Signals & Registers -- //

  localparam ST_IDLE = 0;
  localparam ST_DONE = 1;
  localparam ST_WDAT = 2;
  localparam ST_RESP = 3;
  localparam ST_RADR = 4;
  localparam ST_RDAT = 5;
  localparam ST_REND = 6;

  reg bvalid;
  reg [1:0] bresp;
  reg [3:0] bid, tid_q;
  wire bready_w, awvalid_w, wvalid_w, wlast_w, arvalid_w, rready_w;
  wire [3:0] awid_w, arid_w;
  wire [7:0] awlen_w, arlen_w;

  reg vld_q, lst_q;
  reg [1:0] res_q;
  reg [MSB:0] dat_q;
  integer count;
  wire [31:0] cnext;

  reg [3:0] state;

`define __spanner_montana
`ifdef __spanner_montana

  always @(posedge mclk) begin
    if (reset) begin
      state  <= ST_IDLE;
      bvalid <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (awvalid_w) begin
            $display("%8t: Address-WRITE Request ('%m')", $time);
            state <= ST_WDAT;
            bid   <= awid_w;
          end else if (arvalid_w) begin
            $display("%8t: Address-READ Request ('%m')", $time);
            state <= ST_RDAT;
          end
        end

        ST_WDAT: begin
          if (wvalid_w && wlast_w) begin
            $display("%8t: Write-DATA Received ('%m')", $time);
            state <= ST_RESP;
          end
        end

        ST_RESP: begin
          bvalid <= 1'b1;
          bresp  <= RESP_OKAY;
          if (bready_w) begin
            $display("%8t: Write-Response Sent ('%m')", $time);
            state <= ST_DONE;
          end
        end

        ST_DONE: begin
          bvalid <= 1'b0;
          bresp  <= 2'dx;
          state  <= ST_IDLE;
          $display("%8t: Write DONE, returning to IDLE ('%m')", $time);
        end

        ST_RDAT: begin
          state <= vld_q && lst_q && rready_w ? ST_REND : state;
        end

        ST_REND: begin
          state <= ST_IDLE;
          $display("%8t: Read DONE, returning to IDLE ('%m')", $time);
        end

        default: begin
          $error("%8t: Error: Invalid 'state' value: %d ('%m')", $time, state);
          $finish;
        end
      endcase
    end
  end

`endif /* __spanner_montana */

  wire [8:0] len_w;

  assign cnext = count + 1;
  assign len_w = arlen_w + 1;

  always @(posedge mclk) begin
    if (reset) begin
      vld_q <= 1'b0;
      lst_q <= 1'b0;
      count <= 0;
      len_q <= 8'd0;
    end else begin
      if (arvalid_w && state == ST_IDLE) begin
        len_q <= len_w;
        tid_q <= arid_w;
        lst_q <= 1'b0;
        res_q <= 2'bx;
        // res_q <= RESP_OKAY;
        dat_q <= $urandom;
        count <= 0;
      end

      if (count < len_q) begin
        vld_q <= 1'b1;
        res_q <= RESP_OKAY;
        if (rready_w) begin
          dat_q <= $urandom;
          lst_q <= cnext >= len_q;
          count <= cnext;
        end
      end else begin
        vld_q <= 1'b0;
        lst_q <= 1'b0;
        res_q <= 2'bx;
        tid_q <= 4'bx;
        dat_q <= 32'bx;
      end
    end
  end

  //
  //  Cores Under Nondestructive Testing
  ///
  wire epi_ready_w, epi_parity_w, epi_stall_w;
  wire epo_ready_w, epo_parity_w, epo_stall_w;

  reg pready_q, pslverr_q, pfinish_q;
  reg [15:0] prdata_q;
  wire penable_w, pwrite_w;
  wire [ 1:0] pstrb_w;
  wire [31:0] paddr_w;
  wire [15:0] pwdata_w;

  always @(posedge pclk) begin
    if (!presetn) begin
      pready_q  <= 1'b0;
      pslverr_q <= 1'b0;
      pfinish_q <= 1'b0;
      prdata_q  <= 16'bx;
    end else if (penable_w && !pfinish_q) begin
      pready_q  <= 1'b1;
      pslverr_q <= 1'b0;
      pfinish_q <= 1'b1;
      prdata_q  <= pwrite_w ? prdata_q : $random;
    end else begin
      pready_q  <= 1'b0;
      pslverr_q <= 1'b0;
      pfinish_q <= penable_w;
      prdata_q  <= 16'bx;
    end
  end

  usb_mmio U_REQ1 (
      .areset_n(areset_n),  // Global, asynchronous reset (active LOW)

      .clock(clock),  // USB clock domain
      .reset(reset),

      .usb_ack_sent_i(ack_sent_q),
      .usb_ack_recv_i(ack_recv_q),

      .epi_set_conf_i(set_conf_q),
      .epi_clr_conf_i(clr_conf_q),
      .epi_selected_i(epi_sel_q),
      .epi_timedout_i(timeout_q),
      .epi_max_size_i(10'd64),  // Todo
      .epi_ready_o(epi_ready_w),
      .epi_parity_o(epi_parity_w),
      .epi_stalled_o(epi_stall_w),

      .epo_set_conf_i(set_conf_q),
      .epo_clr_conf_i(clr_conf_q),
      .epo_selected_i(epo_sel_q),
      .epo_rx_error_i(epo_err_q),
      .epo_max_size_i(10'd64),  // Todo
      .epo_ready_o(epo_ready_w),
      .epo_parity_o(epo_parity_w),
      .epo_stalled_o(epo_stall_w),

      // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
      .usb_tvalid_i(s_tvalid),
      .usb_tready_o(s_tready),
      .usb_tkeep_i (s_tkeep),
      .usb_tlast_i (s_tlast),
      .usb_tdata_i (s_tdata),

      // USB status, and READ, packet stream (Bulk-Out pipe, AXI-S)
      .usb_tvalid_o(m_tvalid),
      .usb_tready_i(m_tready),
      .usb_tkeep_o (m_tkeep),
      .usb_tlast_o (m_tlast),
      .usb_tdata_o (m_tdata),

      // APB clock domain
      .pclk(pclk),
      .presetn(presetn),

      // APB requester interface, to controllers
      .penable_o(penable_w),
      .pwrite_o (pwrite_w),
      .pstrb_o  (pstrb_w),
      .pready_i (pready_q),
      .pslverr_i(pslverr_q),
      .paddr_o  (paddr_w),
      .pwdata_o (pwdata_w),
      .prdata_i (prdata_q),

      .aclk(mclk),  // AXI clock domain

      .axi_awvalid_o(awvalid_w),
      .axi_awready_i(1'b1),
      .axi_awaddr_o(),
      .axi_awid_o(awid_w),
      .axi_awlen_o(awlen_w),
      .axi_awburst_o(),

      .axi_wvalid_o(wvalid_w),
      .axi_wready_i(1'b1),
      .axi_wlast_o (wlast_w),
      .axi_wstrb_o (),
      .axi_wdata_o (),

      .axi_bvalid_i(bvalid),
      .axi_bready_o(bready_w),
      .axi_bresp_i(bresp),
      .axi_bid_i(bid),

      .axi_arvalid_o(arvalid_w),
      .axi_arready_i(1'b1),
      .axi_araddr_o(),
      .axi_arid_o(arid_w),
      .axi_arlen_o(arlen_w),
      .axi_arburst_o(),

      .axi_rvalid_i(vld_q),
      .axi_rready_o(rready_w),
      .axi_rlast_i(lst_q),
      .axi_rresp_i(res_q),
      .axi_rid_i(tid_q),
      .axi_rdata_i(dat_q)
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

  task cmd_send;
    input [15:0] len;
    input [3:0] tag;
    input [3:0] cmd;
    input [27:0] adr;
    input [3:0] lun;
    begin
      // Select the OUT EP.
      @(posedge clock);
      s_tvalid <= #2 1'b0;
      s_tkeep <= #2 1'b0;
      s_tlast <= #2 1'b0;
      lim_q <= #2{16'd0, len};
      zdp_q <= #2 len[5:0] == 6'h3f;  // ZDP if transfer ends on USB frame boundary
      epo_sel_q <= #2 1'b1;
      @(negedge clock) $display("%11t: Starting CMD (0x%x, ADR: %7x)", $time, cmd, adr);

      @(posedge clock) begin
        s_tvalid <= #2 1'b1;
        s_tkeep <= #2 1'b1;
        s_tlast <= #2 1'b0;
        cnt_q <= #2 s_tvalid && s_tready ? 11'd1 : 11'd0;
        req_q <= #2{tag, cmd, len, lun, adr, "T", "R", "A", "T"};
        rnd_q <= $urandom;
      end
      @(negedge clock) $display("%11t: Sending CMD (0x%x, ADR: %7x)", $time, cmd, adr);

      while (cnt_q < 11'd10) begin
        @(posedge clock);
        if (s_tready) begin
          cnt_q   <= #2 inc_w[10:0];
          req_q   <= #2{rnd_q, req_q[87:8]};
          rnd_q   <= #2 $urandom;
          s_tlast <= #2 inc_w < 12'd10 ? 1'b0 : 1'b1;
        end
        @(negedge clock);
      end

      @(posedge clock) $display("%11t: Sent CMD", $time);
      s_tvalid <= #2 1'b0;
      s_tkeep <= #2 1'b0;
      s_tlast <= #2 1'b0;
      req_q <= #2{rnd_q, req_q[87:8]};

      // Todo: the target device is supposed to 'ACK' the command frame.
      @(negedge clock) #32 $display("%11t: Sending USB ACK", $time);
      @(posedge clock) ack_sent_q <= #2 1'b1;
      #16 ack_sent_q <= #2 1'b0;

      @(posedge clock) #32 epo_sel_q <= #2 1'b0;
    end
  endtask  /* cmd_send */

  /**
   * Read back a response, after a command has completed.
   */
  reg [55:0] din_q;

  task res_recv;
    begin
      // Select the IN EP.
      @(posedge clock) begin
        m_tready  <= #2 1'b0;
        epi_sel_q <= #2 1'b1;
      end
      @(negedge clock) $display("%11t: Requesting RES", $time);

      @(posedge clock) begin
        m_tready <= #2 1'b1;
        cnt_q <= #2 m_tvalid && m_tready ? 11'd1 : 11'd0;
        din_q <= #2 m_tvalid && m_tready ? {m_tdata, 48'bx} : 56'bx;
      end
      @(negedge clock) $display("%11t: Receiving RES", $time);

      while (cnt_q < 11'd6) begin
        @(posedge clock);
        if (m_tvalid) begin
          cnt_q <= #2 inc_w[10:0];
          din_q <= #2{m_tdata, din_q[55:8]};
        end
        @(negedge clock);
      end
      if (m_tvalid && m_tready && m_tlast) begin
        @(posedge clock) $display("%11t: Received RES", $time);
        m_tready <= #2 1'b0;
        din_q <= #2{m_tdata, din_q[55:8]};
      end else begin
        #32 $error("%11t: Invalid transfer: %x", din_q);
        #32 $fatal(1);
      end

      // Todo: the target device is supposed to 'ACK' the command frame.
      @(negedge clock) #32 $display("%11t: Receiving USB ACK", $time);
      @(posedge clock) ack_recv_q <= #2 1'b1;
      #16 ack_recv_q <= #2 1'b0;

      @(posedge clock) #32 epi_sel_q <= #2 1'b0;
    end
  endtask  /* res_recv */

  /**
   * Send one or more Bulk-Out frames, terminated with a ZDP, if required.
   */
  task dat_send;
    begin
      @(negedge clock) $display("%11t: Sending %d (+1) bytes", $time, lim_q);
      @(posedge clock) begin
        epo_sel_q <= #2 1'b1;
        s_tvalid <= #2 1'b0;
        s_tkeep <= #2 1'b0;
        s_tlast <= #2 1'b0;
        cnt_q <= #2 11'd0;
      end

      @(negedge clock) $display("%11t: Starting transaction", $time);
      @(posedge clock) begin
        s_tvalid <= #2 1'b1;
        s_tkeep <= #2 1'b1;
        s_tlast <= #2 lim_q == 32'd0 ? 1'b1 : 1'b0;
        cnt_q <= #2 s_tvalid && s_tready ? 11'd1 : 11'd0;
      end

      while (!(cnt_q == lim_q[10:0] && s_tready)) begin
        @(posedge clock);
        if (s_tready) begin
          cnt_q   <= #2 inc_w[10:0];
          req_q   <= #2{rnd_q, req_q[87:8]};
          rnd_q   <= #2 $urandom;
          s_tlast <= #2 inc_w < lim_q[11:0] ? 1'b0 : 1'b1;
        end
        @(negedge clock);
      end

      $display("%11t: Finishing transaction", $time);
      @(posedge clock);
      s_tvalid <= #2 1'b0;
      s_tkeep  <= #2 1'b0;
      s_tlast  <= #2 1'b0;

      // Todo: the target device is supposed to 'ACK' the command frame.
      @(negedge clock) #64 $display("%11t: Sending USB ACK", $time);
      @(posedge clock) ack_sent_q <= #2 1'b1;
      #16 ack_sent_q <= #2 1'b0;

      @(negedge clock) #16 $display("%11t: Finished transaction", $time);
      @(posedge clock) epo_sel_q <= #2 1'b0;
    end
  endtask  /* dat_send */

  /**
   * Send a command frame, followed by as many data frames as required.
   */
  task axi_send;
    input [7:0] size;
    input [3:0] tag;
    input [27:0] addr;
    input [3:0] lun;
    begin
      cmd_send({8'd0, size}, tag, `CMD_STORE, addr, lun);
      @(negedge clock) #16 $display("%11t: Finished sending AXI STORE command", $time);

      dat_send(size);
      @(negedge clock) #16 $display("%11t: Finished sending AXI STORE data", $time);

      #32 res_recv();
      @(negedge clock) #16 $display("%11t: Completed AXI STORE, RES: %x", $time, din_q);
    end
  endtask  /* axi_send */

  /**
   * Send a command frame, followed by as many data frames as required.
   */
  task apb_send;
    input [15:0] val;
    input [3:0] tag;
    input [27:0] addr;
    input [3:0] lun;
    begin
      cmd_send(val, tag, `CMD_SET, addr, lun);
      @(negedge clock) #16 $display("%11t: Finished APB SET", $time);

      #32 res_recv();
      $display("%11t: Completed RES: %x", $time, din_q);
    end
  endtask  /* apb_send */

  /**
   * GET a value from a device attached to the APB.
   */
  task apb_recv;
    input [3:0] tag;
    input [27:0] addr;
    input [3:0] lun;
    begin
      cmd_send(16'd0, tag, `CMD_GET, addr, lun);
      @(negedge clock) #16 $display("%11t: Finished APB GET", $time);

      #512 res_recv();
      $display("%11t: Completed RES: %x", $time, din_q);
    end
  endtask  /* apb_recv */

endmodule  /* usb_mmio_tb */
