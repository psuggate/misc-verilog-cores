`timescale 1ns / 100ps
module axis_clean #(
    parameter  WIDTH = 8,
    localparam MSB   = WIDTH - 1,
    parameter  DEPTH = 16,
    localparam ABITS = $clog2(DEPTH),
    localparam ASB   = ABITS - 1,
    parameter  REGS  = DEPTH > 32 ? 3 : 0
) (
    input clock,
    input reset,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input s_tkeep,
    input [MSB:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output m_tkeep,
    output [MSB:0] m_tdata
);

  // -- Signals & State -- //

  reg xvalid, xlast;
  reg [MSB:0] xdata;
  wire valid_w, ready_w, store_w;
  wire [ASB:0] level_w;

  assign s_tready = ready_w;
  assign m_tkeep  = m_tvalid;


  // -- AXI4-Stream Cleaner -- //

  assign store_w  = !xvalid || valid_w && ready_w;
  assign valid_w  = xvalid && (s_tvalid && s_tkeep || xlast);

  always @(posedge clock) begin
    if (reset) begin
      xvalid <= 1'b0;
      xlast  <= 1'b0;
      xdata  <= 'bx;
    end else begin
      if (s_tvalid && s_tkeep && store_w) begin
        xvalid <= 1'b1;
        xlast  <= s_tlast;
        xdata  <= s_tdata;
      end else if (!s_tvalid && store_w) begin
        xvalid <= 1'b0;
        xlast  <= 1'b0;
      end else if (s_tvalid && !s_tkeep && s_tlast && xvalid && !xlast) begin
        xlast <= 1'b1;
      end
    end
  end


  sync_fifo #(
      .WIDTH (WIDTH + 1),
      .ABITS (ABITS),
      .OUTREG(REGS)
  ) U_AXIS_FIFO (
      .clock(clock),
      .reset(reset),

      .level_o(level_w),

      .valid_i(valid_w),
      .ready_o(ready_w),
      .data_i ({xlast, xdata}),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .data_o ({m_tlast, m_tdata})
  );


endmodule  // axis_clean
