`timescale 1ns / 100ps
module ep_bulk_in_tb;

  reg clock = 1;
  reg reset = 0;

  always #5 clock <= ~clock;

  initial begin
    $display("Bulk IN End-Point Testbench:");
    $dumpfile("ep_bulk_in_tb.vcd");
    $dumpvars;

    #800 $finish;
  end

  reg set_conf_q, clr_conf_q;
  reg selected_q, ack_recv_q, timedout_q;
  wire ep_ready_w, parity_w, stalled_w;

  reg s_tvalid, m_tready;
  wire s_tlast;
  reg [7:0] s_tdata;
  wire s_tready, m_tvalid, m_tkeep, m_tlast;
  wire [7:0] m_tdata;

  reg fill, send;
  integer size = 4;

  initial begin
    #10 reset <= 1'b1;
    set_conf_q <= 1'b0;
    clr_conf_q <= 1'b0;
    selected_q <= 1'b0;
    timedout_q <= 1'b0;
    ack_recv_q <= 1'b0;
    m_tready <= 1'b0;
    #15 reset <= 1'b0;

    #10
    if (s_tready || m_tvalid) begin
      $error("EP IN driving bus when IDLE");
      $fatal;
    end

    // -- ENABLE EP IN -- //

    #20 set_conf_q <= 1'b1;
    #10 set_conf_q <= 1'b0;

    #10 fill <= 1'b1; size <= 8;
    #170 fill <= 1'b0;

    #40 send <= 1'b1;
    #10 while (selected_q) #10 ;
    #20 send <= 1'b1;
    #10 while (selected_q) #10 ;
    #20 send <= 1'b1;
    #10 while (selected_q) #10 ;
    #20 send <= 1'b1;
    #10 while (selected_q) #10 ;
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
      wcount <= 0;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      send <= 1'b0;
      selected_q <= 1'b0;
      ack_recv_q <= 1'b0;
      m_tready <= 1'b0;
    end else if (send && !selected_q) begin
      selected_q <= 1'b1;
      ack_recv_q <= 1'b0;
      m_tready <= 1'b1;
    end else if (selected_q) begin
      if (send && m_tvalid && m_tready && m_tlast) begin
        m_tready <= 1'b0;
        send <= 1'b0;
      end else if (!send && !ack_recv_q) begin
        ack_recv_q <= 1'b1;
      end else if (ack_recv_q) begin
        ack_recv_q <= 1'b0;
        selected_q <= 1'b0;
      end
    end
  end


  //
  //  Core Under New Tests
  ///

  ep_bulk_in #(
      .ENABLED(1),
      .PACKET_FIFO_DEPTH(32),
      .MAX_PACKET_LENGTH(8)
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


endmodule  /* ep_bulk_in_tb */
