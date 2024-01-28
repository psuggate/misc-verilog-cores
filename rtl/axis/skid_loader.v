`timescale 1ns / 100ps
/**
 * AXI4-Stream skid-buffer that allows the temporary register to be explicitly
 * loaded.
 * 
 * Note:
 *  - can be used as part of a circuit to prefetch the first byte, for a pull-
 *    based stream;
 *  - parameters allow these pipeline-registers to be bypassed, or for the
 *    explicit-load port to be disabled;
 *  - more general-purpose than just for AXI-S; e.g., used for the USB core;
 */
module skid_loader (
    clock,
    reset,

    s_tvalid,
    s_tready,
    s_tlast,
    s_tdata,

    t_tvalid,
    t_tready,
    t_tlast,
    t_tdata,

    m_tvalid,
    m_tready,
    m_tlast,
    m_tdata
);

  parameter BYPASS = 0;
  parameter LOADER = 1;

  parameter WIDTH = 8;
  localparam MSB = WIDTH - 1;

  parameter RESET_TDATA = 0;
  parameter RESET_VALUE = 'bx;


  input clock;
  input reset;

  input s_tvalid;
  output s_tready;
  input s_tlast;
  input [MSB:0] s_tdata;

  input t_tvalid;
  output t_tready;
  input t_tlast;
  input [MSB:0] t_tdata;

  output m_tvalid;
  input m_tready;
  output m_tlast;
  output [MSB:0] m_tdata;


  generate
    if (BYPASS == 1) begin : g_bypass

      // No registers
      assign m_tvalid = s_tvalid;
      assign s_tready = m_tready;
      assign t_tready = 1'b0;
      assign m_tlast  = s_tlast;
      assign m_tdata  = s_tdata;

      initial begin
        $display("=> Bypassing AXI-S skid-register");
      end
    end // g_bypass
  else begin : g_skid

      assign s_tready = sready;
      assign t_tready = tready;
      assign m_tvalid = mvalid;
      assign m_tlast  = mlast;
      assign m_tdata  = mdata;


      reg sready, tready, mvalid, mlast, tvalid, tlast;
      reg [MSB:0] mdata, tdata;

      wire sready_next, tvalid_next, tready_next, mvalid_next;


      // -- Control -- //

      function src_ready(input svalid, input tvalid, input dvalid, input dready);
        src_ready = dready || !(tvalid || (dvalid && svalid));
      endfunction

      function tmp_ready(input svalid, input tvalid, input dvalid, input dready);
        tmp_ready = (dready || !dvalid) && (!tvalid || !svalid);
      endfunction

      function tmp_valid(input svalid, input tvalid, input dvalid, input dready);
        tmp_valid = !src_ready(svalid, tvalid, dvalid, dready);
      endfunction

      function dst_valid(input svalid, input tvalid, input dvalid, input dready);
        dst_valid = tvalid || svalid || (dvalid && !dready);
      endfunction

      assign sready_next = src_ready(s_tvalid, tvalid, mvalid, m_tready);
      assign tvalid_next = tmp_valid(s_tvalid, tvalid, mvalid, m_tready);
      assign tready_next = tmp_ready(s_tvalid, tvalid, mvalid, m_tready);
      assign mvalid_next = dst_valid(s_tvalid, tvalid, mvalid, m_tready);

      always @(posedge clock) begin
        if (reset) begin
          sready <= 1'b0;
          mvalid <= 1'b0;
          tvalid <= 1'b0;
          tready <= 1'b0;
        end else begin
          sready <= sready_next && !(LOADER && t_tvalid && t_tready);
          mvalid <= mvalid_next;
          tvalid <= tvalid_next || LOADER && t_tvalid && t_tready;
          tready <= tready_next && LOADER && !t_tvalid;
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
        if (RESET_TDATA && reset) begin
          mdata <= RESET_VALUE;
          mlast <= 1'b0;
        end else if (src_to_dst(sready, mvalid, m_tready)) begin
          mdata <= s_tdata;
          mlast <= s_tlast;
        end else if (tmp_to_dst(tvalid, m_tready)) begin
          mdata <= tdata;
          mlast <= tlast;
        end

        if (LOADER && t_tready && t_tvalid) begin
          tdata <= t_tdata;
          tlast <= t_tlast;
        end else if (src_to_tmp(sready, mvalid, m_tready)) begin
          tdata <= s_tdata;
          tlast <= s_tlast;
        end
      end

    end  // g_skid
  endgenerate

endmodule  // skid_loader
