`timescale 1ns / 100ps
module ep_bulk_in_tb;

  localparam PACKET_FIFO_DEPTH = 32;
  localparam MAX_PACKET_LENGTH = 8;

  reg clock = 1;
  reg reset = 0;

  always #5 clock <= ~clock;

  initial begin
    $display("Bulk IN End-Point Testbench:");
    $dumpfile("ep_bulk_in_tb.vcd");
    $dumpvars;

    #1200 $finish;
  end

  reg set_conf_q, clr_conf_q;
  reg selected_q, ack_recv_q, timedout_q;
  wire ep_ready_w, parity_w, stalled_w;

  reg s_tvalid, m_tready;
  wire s_tlast;
  reg [7:0] s_tdata;
  wire s_tready, m_tvalid, m_tkeep, m_tlast;
  wire [7:0] m_tdata;

  reg fill, send, fail;
  integer size = 4;

  initial begin
    #10 reset <= 1'b1;
    set_conf_q <= 1'b0;
    clr_conf_q <= 1'b0;
    selected_q <= 1'b0;
    timedout_q <= 1'b0;
    ack_recv_q <= 1'b0;
    m_tready   <= 1'b0;
    #15 reset <= 1'b0;

    #10
    if (s_tready || m_tvalid) begin
      $error("EP IN driving bus when IDLE");
      $fatal;
    end

    // -- ENABLE EP IN -- //

    #20 set_conf_q <= 1'b1;
    #10 set_conf_q <= 1'b0;

    #10 fill <= 1'b1;
    size <= 16;
    #170 fill <= 1'b0;

    // Send first packet, and its ZDP
    #40 send <= 1'b1;
    #10 while (selected_q) #10;
    #20 send <= 1'b1;
    #10 while (selected_q) #10;

    // Send second packet, replaying on timeout, then its ZDP
    #20 send <= 1'b1;
    fail <= 1'b1;
    #10 while (selected_q) #10;
    #20 send <= 1'b1;
    #10 while (selected_q) #10;
    #20 send <= 1'b1;
    #10 while (selected_q) #10;
  end

  integer wcount;
  wire [31:0] wcnext = wcount + 1;

  assign s_tlast = wcnext == size;

  always @(posedge clock) begin
    if (reset) begin
      fill <= 1'b0;
      wcount <= 0;
      s_tvalid <= 1'b0;
      s_tdata <= 'bx;
    end else if (fill && s_tready) begin
      s_tvalid <= 1'b1;
      s_tdata  <= $urandom;
      if (s_tvalid && s_tready) begin
        wcount <= s_tlast ? 0 : wcnext;
      end
    end else if (!fill) begin
      s_tvalid <= 1'b0;
      wcount   <= 0;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      send <= 1'b0;
      fail <= 1'b0;
      selected_q <= 1'b0;
      ack_recv_q <= 1'b0;
      timedout_q <= 1'b0;
      m_tready <= 1'b0;
    end else if (send && !selected_q) begin
      selected_q <= 1'b1;
      ack_recv_q <= 1'b0;
      timedout_q <= 1'b0;
      m_tready   <= 1'b1;
    end else if (selected_q) begin
      if (send && m_tvalid && m_tready && m_tlast) begin
        m_tready <= 1'b0;
        send <= 1'b0;
      end else if (!send && !ack_recv_q && !timedout_q) begin
        ack_recv_q <= ~fail;
        timedout_q <= fail;
      end else if (ack_recv_q || timedout_q) begin
        ack_recv_q <= 1'b0;
        timedout_q <= 1'b0;
        selected_q <= 1'b0;
        fail <= 1'b0;
      end
    end
  end


  //
  //  Cores Under New Tests
  ///

  ep_bulk_in #(
      .ENABLED(1),
      .PACKET_FIFO_DEPTH(PACKET_FIFO_DEPTH),
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH)
  ) U_EPIN1 (
      .clock(clock),
      .reset(reset),

      .set_conf_i(set_conf_q),  // From CONTROL PIPE0
      .clr_conf_i(clr_conf_q),  // From CONTROL PIPE0
      .selected_i(selected_q),  // From USB controller
      .timedout_i(timedout_q),  // From USB controller
      .ack_recv_i(ack_recv_q),  // From USB decoder

      .ep_ready_o(ep_ready_w),
      .parity_o  (parity_w),
      .stalled_o (stalled_w),

      .s_tvalid(s_tvalid),  // From Bulk IN data source
      .s_tready(s_tready),
      .s_tlast (s_tlast),
      .s_tdata (s_tdata),

      .m_tvalid(m_tvalid),  // To USB encoder
      .m_tready(m_tready),
      .m_tkeep (m_tkeep),
      .m_tlast (m_tlast),
      .m_tdata (m_tdata)
  );

  // -- Bulk OUT End-Point for Data Loopback -- //

  reg out_sel_q, out_ack_q, out_err_q;
  wire out_rdy_w, out_par_w, out_hlt_w;
  reg o_tready;
  wire tready_w, x_tvalid, x_tready, x_tlast, x_tkeep, o_tvalid, o_tlast;
  wire [7:0] x_tdata, o_tdata;

  assign x_tkeep = x_tvalid;

  always @(posedge clock) begin
    if (reset) begin
      out_sel_q <= 1'b0;
      out_ack_q <= 1'b0;
      out_err_q <= 1'b0;
      o_tready  <= 1'b0;
    end else begin
      if (m_tvalid) begin
        out_sel_q <= 1'b1;
      end else if (out_ack_q) begin
        out_sel_q <= 1'b0;
      end

      out_ack_q <= x_tvalid && x_tready && x_tlast;
      out_err_q <= timedout_q;

      if (out_sel_q) begin
        o_tready <= 1'b1;
      end

      if (m_tvalid && m_tready && !tready_w) begin
        $error("%8t: Data transfer when EP OUT not ready", $time);
      end
    end
  end

  packet_fifo #(
      .WIDTH(8),
      .DEPTH(PACKET_FIFO_DEPTH),
      .STORE_LASTS(1),
      .SAVE_ON_LAST(1),  // save only after CRC16 checking
      .LAST_ON_SAVE(0),  // delayed 'tlast', after CRC16-valid
      .NEXT_ON_LAST(1),
      .USE_LENGTH(0),
      .MAX_LENGTH(MAX_PACKET_LENGTH),
      .OUTREG(2)
  ) U_FIFO1 (
      .clock(clock),
      .reset(reset),

      .level_o(),

      .drop_i(1'b0),
      .save_i(1'b0),
      .redo_i(1'b0),
      .next_i(1'b0),

      .s_tvalid(m_tvalid),
      .s_tready(tready_w),
      .s_tkeep (m_tkeep),
      .s_tlast (m_tlast),
      .s_tdata (m_tdata),

      .m_tvalid(x_tvalid),
      .m_tready(x_tready),
      .m_tlast (x_tlast),
      .m_tdata (x_tdata)
  );

  ep_bulk_out #(
      .MAX_PACKET_LENGTH(MAX_PACKET_LENGTH),
      .PACKET_FIFO_DEPTH(PACKET_FIFO_DEPTH),
      .ENABLED(1)
  ) U_EPOUT1 (
      .clock(clock),
      .reset(reset),

      .set_conf_i(set_conf_q),
      .clr_conf_i(clr_conf_q),

      .selected_i(out_sel_q),
      .ack_sent_i(out_ack_q),  // Todo ...
      .rx_error_i(out_err_q),
      .ep_ready_o(out_rdy_w),
      .parity_o  (out_par_w),
      .stalled_o (out_hlt_w),

      .s_tvalid(x_tvalid),
      .s_tready(x_tready),
      .s_tkeep (x_tkeep),
      .s_tlast (x_tlast),
      .s_tdata (x_tdata),

      .m_tvalid(o_tvalid),
      .m_tready(o_tready),
      .m_tlast (o_tlast),
      .m_tdata (o_tdata)
  );


endmodule  /* ep_bulk_in_tb */
