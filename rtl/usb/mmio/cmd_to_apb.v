`timescale 1ns / 100ps
module cmd_to_apb (  // USB bus (command) clock-domain
    // Global asynchronous reset
    input areset_n,

    // USB-domain clock & reset signals
    input cmd_clk,
    input cmd_rst,

    // Decoded command (APB, or AXI)
    input cmd_vld_i,
    input cmd_ack_i,
    input cmd_dir_i,
    input [1:0] cmd_cmd_i,
    input [3:0] cmd_tag_i,
    input [15:0] cmd_val_i,
    input [27:0] cmd_adr_i,
    input [3:0] cmd_lun_i,
    output cmd_rdy_o,
    output cmd_err_o,
    output [15:0] cmd_val_o,

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
    input [15:0] prdata_i
);

  reg vld_q, rdy_q, err_q, cyc_p;
  reg [15:0] val_q;
  wire rdy_w;

  localparam [3:0] ST_IDLE = 4'd1, ST_READ = 4'd2, ST_WRIT = 4'd4, ST_DONE = 4'd8;
  reg [3:0] state;

  wire cvalid_w, cready_w, cwrite_w, cerror_w;
  wire [15:0] crdata_w;

  wire pwrite_w, pvalid_w, pready_w, perror_w, strobe_w;
  wire [15:0] pwdata_w;
  wire [31:0] paddr_w;

  // APB-domain signal assignments.
  assign penable_o = cyc_p;
  assign pwrite_o  = pwrite_w;
  assign pstrb_o   = {pwrite_w, pwrite_w};
  assign pwdata_o  = pwdata_w;
  assign paddr_o   = paddr_w;

  // USB-domain signal assignments.
  assign cmd_rdy_o = rdy_q;
  assign cmd_err_o = err_q;
  assign cmd_val_o = val_q;

  /**
   * Transaction-framing logic, for APB requests.
   */
  always @(posedge cmd_clk or negedge areset_n) begin
    if (!areset_n || cmd_rst) begin
      vld_q <= 1'b0;
      rdy_q <= 1'b0;
      val_q <= 16'bx;
      err_q <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          vld_q <= cmd_vld_i && rdy_w;
          rdy_q <= 1'b0;
          val_q <= 16'bx;
          err_q <= cmd_ack_i ? 1'b0 : err_q;
        end
        ST_READ: begin
          vld_q <= 1'b0;
          rdy_q <= cvalid_w && !cwrite_w && !cerror_w;
          val_q <= crdata_w;
          err_q <= cvalid_w && (cwrite_w || cerror_w);
        end
        ST_WRIT: begin
          vld_q <= 1'b0;
          rdy_q <= 1'b0;
          val_q <= 16'bx;
          err_q <= cvalid_w && (!cwrite_w || cerror_w);
        end
        ST_DONE: begin
          vld_q <= 1'b0;
          rdy_q <= 1'b0;
          val_q <= val_q;
          err_q <= err_q;
        end
      endcase
    end
  end

  /**
   * USB-domain FSM, for processing APB transactions.
   */
  always @(posedge cmd_clk) begin
    if (cmd_rst || !cmd_vld_i || !rdy_w || err_q) begin
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE: state <= cmd_dir_i ? ST_READ : ST_WRIT;
        ST_READ: state <= cvalid_w ? ST_DONE : state;
        ST_WRIT: state <= cvalid_w ? ST_DONE : state;
        ST_DONE: state <= state;
      endcase
    end
  end


  //
  //  APB-domain logic.
  //
  assign perror_w = pslverr_i || !presetn;
  assign strobe_w = cyc_p && (pready_i && pslverr_i || !presetn);

  always @(posedge pclk or negedge areset_n) begin
    if (!areset_n) begin
      cyc_p <= 1'b0;
    end else begin
      if (pvalid_w && pready_w) begin
        cyc_p <= 1'b1;
      end else if (strobe_w) begin
        cyc_p <= 1'b0;
      end
    end
  end

  // APB-requests FIFO.
  axis_afifo #(
      .WIDTH(49),
      .TLAST(0),
      .ABITS(4)
  ) U_AFIFO0 (
      .aresetn(areset_n),

      .s_aclk  (cmd_clk),
      .s_tvalid(vld_q),
      .s_tready(rdy_w),
      .s_tlast (1'b1),
      .s_tdata ({~cmd_dir_i, cmd_lun_i, cmd_adr_i, cmd_val_i}),

      .m_aclk  (pclk),
      .m_tvalid(pvalid_w),
      .m_tready(strobe_w),
      .m_tlast (),
      .m_tdata ({pwrite_w, paddr_w, pwdata_w})
  );

  // APB-response FIFO.
  axis_afifo #(
      .WIDTH(18),
      .TLAST(0),
      .ABITS(4)
  ) U_AFIFO1 (
      .aresetn(areset_n),

      .s_aclk  (pclk),
      .s_tvalid(strobe_w),
      .s_tready(pready_w),
      .s_tlast (1'b1),
      .s_tdata ({perror_w, pwrite_w, prdata_i}),

      .m_aclk  (cmd_clk),
      .m_tvalid(cvalid_w),
      .m_tready(cready_w),
      .m_tlast (),
      .m_tdata ({cerror_w, cwrite_w, crdata_w})
  );


endmodule  /* cmd_to_apb */
