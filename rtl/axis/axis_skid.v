`timescale 1ns / 100ps
module axis_skid (
    clock,
    reset,

    s_tvalid,
    s_tready,
    s_tlast,
    s_tdata,

    m_tvalid,
    m_tready,
    m_tlast,
    m_tdata
);

  parameter BYPASS = 0;

  parameter WIDTH = 8;
  localparam MSB = WIDTH - 1;


  input clock;
  input reset;

  input s_tvalid;
  output s_tready;
  input s_tlast;
  input [MSB:0] s_tdata;

  output m_tvalid;
  input m_tready;
  output m_tlast;
  output [MSB:0] m_tdata;


  generate
    if (BYPASS == 1) begin : g_bypass

      // No registers
      assign m_tvalid = s_tvalid;
      assign s_tready = m_tready;
      assign m_tlast  = s_tlast;
      assign m_tdata  = s_tdata;

      initial begin
        $display("=> Bypassing AXI-S skid-register");
      end
    end // g_bypass
  else begin : g_skid

      assign s_tready = sready;
      assign m_tvalid = mvalid;
      assign m_tlast  = mlast;
      assign m_tdata  = mdata;


      reg sready, mvalid, mlast, tvalid, tlast;
      reg [MSB:0] mdata, tdata;

      wire sready_next, tvalid_next, mvalid_next;


      // -- Control -- //

      function src_ready(input svalid, input tvalid, input dvalid, input dready);
        src_ready = dready || !(tvalid || (dvalid && svalid));
      endfunction

      function tmp_valid(input svalid, input tvalid, input dvalid, input dready);
        tmp_valid = !src_ready(svalid, tvalid, dvalid, dready);
      endfunction

      function dst_valid(input svalid, input tvalid, input dvalid, input dready);
        dst_valid = tvalid || svalid || (dvalid && !dready);
      endfunction

      assign sready_next = src_ready(s_tvalid, tvalid, mvalid, m_tready);
      assign tvalid_next = tmp_valid(s_tvalid, tvalid, mvalid, m_tready);
      assign mvalid_next = dst_valid(s_tvalid, tvalid, mvalid, m_tready);

      always @(posedge clock) begin
        if (reset) begin
          sready <= 1'b0;
          mvalid <= 1'b0;
          tvalid <= 1'b0;
        end else begin
          sready <= sready_next;
          mvalid <= mvalid_next;
          tvalid <= tvalid_next;
        end
      end


      // -- Datapath -- //

      function src_to_tmp(input src_ready, input dst_valid, input dst_ready);
        src_to_tmp = src_ready && !dst_ready && dst_valid;
      endfunction

      function tmp_to_dst(input tmp_valid, input dst_ready);
        tmp_to_dst = tmp_valid && dst_ready;
      endfunction

      function src_to_dst(input src_ready, input dst_valid, input dst_ready);
        src_to_dst = src_ready && (dst_ready || !dst_valid);
      endfunction

      always @(posedge clock) begin
        if (src_to_dst(sready, mvalid, m_tready)) begin
          mdata <= s_tdata;
          mlast <= s_tlast;
        end else if (tmp_to_dst(tvalid, m_tready)) begin
          mdata <= tdata;
          mlast <= tlast;
        end

        if (src_to_tmp(sready, mvalid, m_tready)) begin
          tdata <= s_tdata;
          tlast <= s_tlast;
        end
      end

    end  // g_skid
  endgenerate

endmodule  // axis_skid
