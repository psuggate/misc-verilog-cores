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
    input areset_n,  // Global, asynchronous reset (active LOW)

    input clock,
    input reset,

    input usb_ack_sent_i,
    input usb_ack_recv_i,

    input epi_set_conf_i,
    input epi_clr_conf_i,
    input epi_selected_i,
    input epi_timedout_i,
    input [9:0] epi_max_size_i,
    output epi_ready_o,
    output epi_parity_o,
    output epi_stalled_o,

    input epo_set_conf_i,
    input epo_clr_conf_i,
    input epo_selected_i,
    input epo_rx_error_i,
    input [9:0] epo_max_size_i,
    output epo_ready_o,
    output epo_parity_o,
    output epo_stalled_o,

    // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
    input usb_tvalid_i,
    output usb_tready_o,
    input usb_tkeep_i,
    input usb_tlast_i,
    input [7:0] usb_tdata_i,

    // USB status, and READ, packet stream (Bulk-Out pipe, AXI-S)
    output usb_tvalid_o,
    input usb_tready_i,
    output usb_tkeep_o,
    output usb_tlast_o,
    output [7:0] usb_tdata_o,

    // APB clock-domain
    input pclk,
    input presetn,

    // APB requester interface, to controllers
    output penable_o,
    output pwrite_o,
    output [1:0] pstrb_o,
    input pready_i,
    input pslverr_i,
    output [31:0] paddr_o,
    output [15:0] pwdata_o,
    input [15:0] prdata_i,

    // AXI clock-domain
    input aclk,

    // AXI4 Interface
    output axi_awvalid_o,
    input axi_awready_i,
    output [31:0] axi_awaddr_o,
    output [3:0] axi_awid_o,
    output [7:0] axi_awlen_o,
    output [1:0] axi_awburst_o,

    output axi_wvalid_o,
    input axi_wready_i,
    output axi_wlast_o,
    output [3:0] axi_wstrb_o,
    output [31:0] axi_wdata_o,

    input axi_bvalid_i,
    output axi_bready_o,
    input [1:0] axi_bresp_i,
    input [3:0] axi_bid_i,

    output axi_arvalid_o,
    input axi_arready_i,
    output [31:0] axi_araddr_o,
    output [3:0] axi_arid_o,
    output [7:0] axi_arlen_o,
    output [1:0] axi_arburst_o,

    input axi_rvalid_i,
    output axi_rready_o,
    input axi_rlast_i,
    input [1:0] axi_rresp_i,
    input [3:0] axi_rid_i,
    input [31:0] axi_rdata_i
);

  reg sel_apb_q, sel_axi_q, cmd_ack_q;
  wire cmd_vld_w, cmd_ack_w, cmd_dir_w, cmd_apb_w, cmd_rdy_w, cmd_err_w;
  wire [1:0] cmd_cmd_w;
  wire [15:0] cmd_len_w, cmd_val_w;
  wire [3:0] cmd_tag_w, cmd_lun_w;
  wire [27:0] cmd_adr_w;

  reg busy_q, send_q, done_q;
  wire recv_w, sent_w, resp_w;
  wire s_tvalid, s_tready, s_tkeep, s_tlast;
  wire m_tvalid, m_tready, m_tkeep, m_tlast;
  wire [7:0] s_tdata, m_tdata;

  localparam [4:0] ST_IDLE = 5'd1, ST_READ = 5'd2, ST_WAIT = 5'd4, ST_RESP = 5'd8, ST_HALT = 5'd16;
  reg [4:0] state;
  reg epi_en_q, epo_en_q, clear;


  //
  //  Module control-signals.
  //
  always @(posedge clock or negedge areset_n) begin
    if (reset || !areset_n || epo_set_conf_i || epo_clr_conf_i || epi_set_conf_i || epi_clr_conf_i) begin
      clear <= 1'b1;
    end else begin
      clear <= 1'b0;
    end
  end

  always @(posedge clock) begin
    if (epo_set_conf_i) begin
      epo_en_q <= 1'b1;
    end else if (reset || epo_clr_conf_i || epo_stalled_o) begin
      epo_en_q <= 1'b0;
    end

    if (epi_set_conf_i) begin
      epi_en_q <= 1'b1;
    end else if (reset || epi_clr_conf_i || epi_stalled_o) begin
      epi_en_q <= 1'b0;
    end

    if (clear) begin
      busy_q <= 1'b0;
      send_q <= 1'b0;
      done_q <= 1'b0;
    end else begin
      if (cmd_ack_w) begin
        busy_q <= 1'b0;
        done_q <= 1'b1;
      end else if (cmd_vld_w) begin
        busy_q <= 1'b1;
        done_q <= 1'b0;
      end else begin
        busy_q <= busy_q;
        done_q <= 1'b0;
      end

      if (recv_w || cmd_rdy_w || cmd_err_w) begin
        send_q <= 1'b1;
      end else begin  // if (sent_w) begin
        send_q <= 1'b0;
      end
    end
  end


  //
  //  Simple FSM to handle one command at a time.
  //
  always @(posedge clock) begin
    if (reset) begin
      state <= ST_HALT;
    end else begin
      case (state)
        ST_IDLE: begin
          // When CMD received, issue:
          //  a) SET   => APB write, GOTO wait
          //  b) GET   => APB read, GOTO read
          //  c) FETCH => AXI read, GOTO wait
          //  d) STORE => AXI write, GOTO wait
          if (cmd_vld_w) begin
            state <= cmd_apb_w || !cmd_dir_w ? ST_WAIT : ST_READ;
          end
        end

        ST_READ: begin
          // For 'GET', 'READY', and 'QUERY' requests.
          if (cmd_apb_w && pready_i) begin
            state <= ST_RESP;
          end
        end

        ST_WAIT:
        if (recv_w || sent_w) begin
          state <= ST_RESP;
        end

        ST_RESP:
        if (resp_w) begin
          state <= ST_IDLE;
        end

        ST_HALT:
        if (epo_en_q && epi_en_q) begin
          state <= ST_IDLE;
        end
      endcase
    end
  end


  //
  //  The MMIO interface requires two USB end-points, a Bulk-In and a Bulk-Out
  //  end-point.
  //
  mmio_ep_out U_EPOUT0 (
      .clock(clock),
      .reset(reset),

      .set_conf_i(epo_set_conf_i),  // From CONTROL PIPE0
      .clr_conf_i(epo_clr_conf_i),  // From CONTROL PIPE0
      .max_size_i(epo_max_size_i),  // Todo: From CONTROL PIPE0

      .selected_i(epo_selected_i),  // From USB controller
      .rx_error_i(epo_rx_error_i),  // Timed-out or CRC16 error
      .ack_sent_i(usb_ack_sent_i),

      .ep_ready_o(epo_ready_o),
      .parity_o  (epo_parity_o),
      .stalled_o (epo_stalled_o), // If invariants violated

      // From MMIO controller
      .mmio_busy_i(busy_q),  // Todo: what do I want?
      .mmio_recv_o(recv_w),
      .mmio_sent_i(sent_w),
      .mmio_resp_i(resp_w),
      .mmio_done_i(done_q),

      // USB command, and WRITE, packet stream (Bulk-In pipe, AXI-S)
      .usb_tvalid_i(usb_tvalid_i),
      .usb_tready_o(usb_tready_o),
      .usb_tkeep_i (usb_tkeep_i),
      .usb_tlast_i (usb_tlast_i),
      .usb_tdata_i (usb_tdata_i),

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
      .dat_tvalid_o(m_tvalid),
      .dat_tready_i(m_tready),
      .dat_tkeep_o (m_tkeep),
      .dat_tlast_o (m_tlast),
      .dat_tdata_o (m_tdata)
  );

  mmio_ep_in U_EPIN0 (
      .clock(clock),
      .reset(reset),

      .set_conf_i(epi_set_conf_i),  // From CONTROL PIPE0
      .clr_conf_i(epi_clr_conf_i),  // From CONTROL PIPE0
      .max_size_i(epi_max_size_i),  // Todo: From CONTROL PIPE0

      .selected_i(epi_selected_i),  // From USB controller
      .timedout_i(epi_timedout_i),  // Timed-out or CRC16 error
      .ack_recv_i(usb_ack_recv_i),
      .ack_sent_i(usb_ack_sent_i),

      .ep_ready_o(epi_ready_o),
      .parity_o  (epi_parity_o),
      .stalled_o (epi_stalled_o), // If invariants violated

      // From MMIO controller
      .mmio_busy_i(busy_q),
      .mmio_recv_i(recv_w),
      .mmio_send_i(send_q),
      .mmio_sent_o(sent_w),
      .mmio_resp_o(resp_w),
      .mmio_done_i(done_q),

      // From Bulk-In data source (AXI or APB(), via AXI-S)
      .dat_tvalid_i(s_tvalid),
      .dat_tready_o(s_tready),
      .dat_tkeep_i (s_tkeep),
      .dat_tlast_i (s_tlast),
      .dat_tdata_i (s_tdata),

      // Decoded command (APB(), or AXI)
      .cmd_vld_i(cmd_vld_w),
      .cmd_ack_i(cmd_ack_q),
      .cmd_dir_i(cmd_dir_w),
      .cmd_apb_i(cmd_apb_w),
      .cmd_cmd_i(cmd_cmd_w),
      .cmd_tag_i(cmd_tag_w),
      .cmd_len_i(cmd_len_w),
      .cmd_lun_i(cmd_lun_w),
      .cmd_rdy_i(cmd_rdy_w),
      .cmd_err_i(cmd_err_w),
      .cmd_val_i(cmd_val_w),

      // Output data stream (via AXI-S(), to Bulk-In)(), and USB data or responses
      .usb_tvalid_o(usb_tvalid_o),
      .usb_tready_i(usb_tready_i),
      .usb_tkeep_o (usb_tkeep_o),
      .usb_tlast_o (usb_tlast_o),
      .usb_tdata_o (usb_tdata_o)
  );


  //
  //  Controllers for the APB and AXI transactions.
  //
  assign cmd_ack_w = state == ST_RESP && resp_w;

  /**
   * Command-processing logic, for GET, QUERY, and READY requests.
   */
  always @(posedge clock) begin
    if (reset) begin
      cmd_ack_q <= 1'b0;
    end else begin
      cmd_ack_q <= cmd_ack_w;
    end
  end

  /**
   * Select the controller for the transaction, either the APB or the AXI.
   */
  always @(posedge clock) begin
    if (reset || cmd_ack_w) begin
      sel_apb_q <= 1'b0;
      sel_axi_q <= 1'b0;
    end else begin
      // if (!sel_apb_q && cmd_vld_w && cmd_apb_w) begin
      if (cmd_vld_w && cmd_apb_w) begin
        sel_apb_q <= 1'b1;
      end
      // if (!sel_axi_q && cmd_vld_w && !cmd_apb_w) begin
      if (cmd_vld_w && !cmd_apb_w) begin
        sel_axi_q <= 1'b1;
      end
    end
  end

  /**
   * Issues APB transactions, then sends the result to Bulk-In EP.
   */
  cmd_to_apb U_APB_CTRL0 (
      .areset_n(areset_n),  // Global, asynchronous reset (active LOW)

      .cmd_clk(clock),  // USB bus (command) clock-domain
      .cmd_rst(reset),

      .cmd_vld_i(sel_apb_q),  // Decoded command (APB(), or AXI)
      .cmd_ack_i(cmd_ack_q),
      .cmd_dir_i(cmd_dir_w),
      .cmd_cmd_i(cmd_cmd_w),
      .cmd_tag_i(cmd_tag_w),
      .cmd_val_i(cmd_len_w),
      .cmd_adr_i(cmd_adr_w),
      .cmd_lun_i(cmd_lun_w),
      .cmd_rdy_o(cmd_rdy_w),
      .cmd_err_o(cmd_err_w),
      .cmd_val_o(cmd_val_w),

      .pclk(pclk),  // APB clock-domain
      .presetn(presetn),  // Synchronous reset (active LOW)

      .penable_o(penable_o),  // APB requester interface(), to controllers
      .pwrite_o (pwrite_o),
      .pstrb_o  (pstrb_o),
      .pready_i (pready_i),
      .pslverr_i(pslverr_i),
      .paddr_o  (paddr_o),
      .pwdata_o (pwdata_o),
      .prdata_i (prdata_i)
  );

`define __spanner_montana
`ifdef __spanner_montana

  /**
   * Issues AXI transactions, transfers data to/from AXI bus, and then sends
   * the result to Bulk-In EP.
   */
  cmd_to_axi U_AXI_CTRL0 (
      .cmd_clk(clock),  // USB bus (command) clock-domain
      .cmd_rst(reset),

      .cmd_vld_i(sel_axi_q),  // Decoded command (APB(), or AXI)
      .cmd_ack_i(cmd_ack_q),
      .cmd_dir_i(cmd_dir_w),
      .cmd_cmd_i(cmd_cmd_w),
      .cmd_tag_i(cmd_tag_w),
      .cmd_len_i(cmd_len_w),
      .cmd_lun_i(cmd_lun_w),

      .dat_tvalid_i(m_tvalid),
      .dat_tready_o(m_tready),
      .dat_tkeep_i (m_tkeep),
      .dat_tlast_i (m_tlast),
      .dat_tdata_i (m_tdata),

      .dat_tvalid_o(s_tvalid),
      .dat_tready_i(s_tready),
      .dat_tkeep_o (s_tkeep),
      .dat_tlast_o (s_tlast),
      .dat_tdata_o (s_tdata),

      .aclk(aclk),  // AXI clock-domain
      .aresetn(areset_n),  // Asynchronous reset (active LOW)

      .awvalid_o(axi_awvalid_o),  // AXI4 Interface
      .awready_i(axi_awready_i),
      .awaddr_o(axi_awaddr_o),
      .awid_o(axi_awid_o),
      .awlen_o(axi_awlen_o),
      .awburst_o(axi_awburst_o),

      .wvalid_o(axi_wvalid_o),
      .wready_i(axi_wready_i),
      .wlast_o (axi_wlast_o),
      .wstrb_o (axi_wstrb_o),
      .wdata_o (axi_wdata_o),

      .bvalid_i(axi_bvalid_i),
      .bready_o(axi_bready_o),
      .bresp_i(axi_bresp_i),
      .bid_i(axi_bid_i),

      .arvalid_o(axi_arvalid_o),
      .arready_i(axi_arready_i),
      .araddr_o(axi_araddr_o),
      .arid_o(axi_arid_o),
      .arlen_o(axi_arlen_o),
      .arburst_o(axi_arburst_o),

      .rvalid_i(axi_rvalid_i),
      .rready_o(axi_rready_o),
      .rlast_i(axi_rlast_i),
      .rresp_i(axi_rresp_i),
      .rid_i(axi_rid_i),
      .rdata_i(axi_rdata_i)
  );

`endif  /* __spanner_montana */

endmodule  /* usb_mmio */
