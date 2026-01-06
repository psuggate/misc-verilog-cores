`timescale 1ns / 100ps
module cmd_to_apb (  // USB bus (command) clock-domain
    input cmd_clk,
    input cmd_rst,

    // Decoded command (APB, or AXI)
    input cmd_vld_i,
    input cmd_ack_i,
    input cmd_dir_i,
    input [1:0] cmd_cmd_i,
    input [3:0] cmd_tag_i,
    input [15:0] cmd_val_i,
    input [3:0] cmd_lun_i,
    output cmd_rdy_o,
    output [15:0] cmd_val_o,

    // APB clock-domain
    input pclk,
    input presetn,

    // APB requester interface, to controllers
    output penable_o,
    output pwrite_o,
    output pstrb_o,
    input pready_i,
    input pslverr_i,
    output [ASB:0] paddr_o,
    output [15:0] pwdata_o,
    input [15:0] prdata_i
);

  reg rdy_q;
  reg [15:0] val_q;

  localparam [4:0] ST_IDLE = 5'd1, ST_READ = 5'd2, ST_WAIT = 5'd4, ST_RESP = 5'd8, ST_HALT = 5'd16;
  reg [4:0] state;

  assign cmd_rdy_o = rdy_q;
  assign cmd_val_o = val_q;

  /**
   * Command-processing logic, for GET, QUERY, and READY requests.
   */
  always @(posedge clock) begin
    if (reset) begin
      rdy_q <= 1'b0;
      val_q <= 16'bx;
    end else if (state == ST_READ && cmd_apb_i && pready_i) begin
      val_q <= prdata_i;
      rdy_q <= 1'b1;
    end else begin
      rdy_q <= 1'b0;
      val_q <= 16'bx;
    end
  end


endmodule  /* cmd_to_apb */
