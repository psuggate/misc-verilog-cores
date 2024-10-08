`timescale 1ns / 100ps
module axis_chop #(
    parameter BYPASS = 0,  // Disable the chopper, and pass all signals through

    parameter MAXLEN = 64,
    localparam LBITS = $clog2(MAXLEN + 1),
    localparam LZERO = {LBITS{1'b0}},
    localparam LSB = LBITS - 1,

    parameter  WIDTH = 8,
    localparam MSB   = WIDTH - 1
) (
    input clock,
    input reset,

    input active_i,
    input [LSB:0] length_i,
    output final_o,

    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [MSB:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [MSB:0] m_tdata
);

  //
  // Chops a transfer at 'length_i'.
  //
  // Note: to resume a chopped transfer, assert 'active_i' with a suitable
  //   'length_i' at least one cycle before asserting 'm_tready' & 's_tvalid'.
  ///

  generate
    if (BYPASS == 1) begin : g_bypass

      // No registers
      assign m_tvalid = s_tvalid;
      assign s_tready = m_tready;
      assign m_tkeep  = s_tkeep;
      assign m_tlast  = s_tlast;
      assign m_tdata  = s_tdata;

      assign final_o  = m_tvalid && m_tready && m_tlast;

      initial begin
        $display("=> Bypassing AXI-S chop-register");
      end

    end // g_bypass
  else begin : g_chop

      reg sready, mvalid, mkeep, mlast, tvalid, tlast;
      reg [MSB:0] mdata, tdata;
      wire sready_next, tvalid_next, mvalid_next;

      assign s_tready = sready;
      assign m_tvalid = mvalid;
      assign m_tkeep  = mkeep;
      assign m_tlast  = mlast;
      assign m_tdata  = mdata;


      // -- Burst Chopper -- //

      reg final_q;
      wire fnext_w, tlast_w;
      reg  [LSB:0] remain_q;
      wire [LSB:0] source_w = active_i ? remain_q : length_i;
      wire [LSB:0] remain_w = source_w - 1;

      assign tlast_w = final_q && s_tvalid && sready || s_tlast;
      assign fnext_w = s_tvalid && sready && !final_q && (remain_w == 0 || s_tlast)
      || final_q && active_i;
      assign final_o = final_q;

      always @(posedge clock) begin
        if (!active_i || s_tvalid && sready && !final_q) begin
          remain_q <= remain_w;
        end

        if (reset || !active_i) begin
          final_q <= 1'b0;
        end else if (s_tvalid && sready && !final_q) begin
          final_q <= remain_w == 0 || s_tlast;
        end
      end


      // -- Burst Framer -- //

      reg frame_q, active_q;

      // Will there be space in either register ('T', or 'M') ??
      assign sready_next = active_i && frame_q && 
                         (!(s_tvalid && mvalid) && !tvalid || m_tready) &&
                         (!final_q || final_q && !sready) &&
                         !(s_tvalid && sready && s_tlast);

      always @(posedge clock) begin
        if (reset) begin
          {frame_q, active_q} <= 2'b00;
        end else begin
          if (active_i && !frame_q && !active_q) begin
            {frame_q, active_q} <= 2'b11;
          end else if ((final_q || s_tlast) && s_tvalid && sready) begin
            {frame_q, active_q} <= {1'b0, active_i};
          end else if (!active_i) begin
            {frame_q, active_q} <= 2'b00;
          end
        end
      end


      // -- Control -- //

      // assign sready_next = active_i && (!final_q || final_q && !sready) &&
      //                      (!(s_tvalid && mvalid || tvalid) || m_tready);
      assign tvalid_next = !m_tready && mvalid && (tvalid || s_tvalid && sready);
      assign mvalid_next = s_tvalid && sready || tvalid || mvalid && !m_tready;

      always @(posedge clock) begin
        if (reset || !active_i) begin
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
        if (reset || mvalid && m_tready && mlast) begin
          mlast <= 1'b0;
          tlast <= 1'b0;
        end else begin
          if (src_to_dst(sready, mvalid, m_tready)) begin
            mdata <= s_tdata;
            mlast <= tlast_w;
          end else if (tmp_to_dst(tvalid, m_tready)) begin
            mdata <= tdata;
            mlast <= tlast;
          end

          if (src_to_tmp(sready, mvalid, m_tready)) begin
            tdata <= s_tdata;
            tlast <= s_tlast;
            tlast <= tlast_w;
          end
        end
      end
    end  // g_chop
  endgenerate


endmodule  // axis_chop
