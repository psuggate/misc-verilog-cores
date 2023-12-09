`timescale 1ns / 100ps
module control_endpoint #(
    parameter [3:0] ENDPOINT = 4'd1
) (
    input clock,
    input reset,

    input  select_i,
    input  start_i,
    output error_o,

    input [ 3:0] req_endpt,
    input [ 7:0] req_type,
    input [ 7:0] req_args,
    input [15:0] req_value,
    input [15:0] req_index,
    input [15:0] req_length,

    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [7:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [7:0] m_tdata
);


  // -- Current USB Configuration State -- //

  reg sel_q;


  // -- Input & Output Assignments -- //

  assign error_o = 1'b0;


  always @(posedge clock) begin
    if (reset) begin
      sel_q <= 1'b0;
    end else begin
    end
  end


  sync_fifo #(
      .WIDTH (9),
      .ABITS (11),
      .OUTREG(3)
  ) rddata_fifo_inst (
      .clock(dev_clock),
      .reset(dev_reset),

      .level_o(flevel),

      .valid_i(mvalid),
      .ready_o(mready),
      .data_i ({mlast, mdata}),

      .valid_o(svalid),
      .ready_i(sready),
      .data_o ({slast, sdata})
  );


endmodule  // control_endpoint
