`timescale 1ns / 100ps
module reqsplit #(
    parameter integer ADDRESS_WIDTH = 28,
    parameter IGNORE_TLAST = 0
) (
    input clock,
    input reset,

    input s_tvalid,
    output s_tready,
    input s_tkeep,
    input s_tlast,
    input [7:0] s_tdata,

    output m_tvalid,
    input m_tready,
    output m_tkeep,
    output m_tlast,
    output [7:0] m_tdata
);

  localparam [7:0] CMD_NOP = 8'h00;
  localparam [7:0] CMD_STORE = 8'h01;
  localparam [7:0] CMD_WDONE = 8'h02;
  localparam [7:0] CMD_WFAIL = 8'h03;
  localparam [7:0] CMD_FETCH = 8'h80;
  localparam [7:0] CMD_RDATA = 8'h81;
  localparam [7:0] CMD_RFAIL = 8'h82;

  localparam CMD_FIFO_WIDTH = ID_WIDTH + ADDRESS_WIDTH + 8 + 1;
  localparam CSB = CMD_FIFO_WIDTH - 1;

  localparam DBITS = $clog2(FIFO_DEPTH);
  localparam DSB = DBITS - 1;

  localparam ST_IDLE = 1;
  localparam ST_WADR = 2;
  localparam ST_WDAT = 4;
  localparam ST_RESP = 8;
  localparam ST_RADR = 16;
  localparam ST_RDAT = 32;
  localparam ST_SEND = 64;
  localparam ST_DONE = 128;

  // -- Datapath Signals -- //

  reg [7:0] state, snext;
  reg [3:0] wr, rd;
  reg [4:0] ptr_q;
  reg cmd_m, rd_m;
  reg wen_q, stb_q, new_q, cyc_q;
  reg mux_q, sel_q, vld_q, lst_q, idx_q;
  reg [  7:0] res_q;
  reg [ISB:0] rid_q;
  reg [7:0] cmd_q, len_q, len_m;
  reg [ISB:0] tid_m;
  reg [ASB:0] adr_m;
  reg [ISB:0] tid_q;  // 4b
  reg [ASB:0] adr_q;  // 28b
  wire mux_enable_w, mux_select_w;
  wire svalid_w, sready_w, fready_w, fvalid_w, rd_mid_w;
  wire [DBITS:0] rd_level_w;
  wire tkeep_w, rvalid_w, cmd_end_w;
  wire bokay_w, wfull_w, rokay_w;
  wire cmd_w, ack_w, rd_w;
  wire wr_cmd_w, wr_ack_w, wr_end_w, rd_cmd_w, rd_ack_w, rd_end_w;
  wire [ISB:0] tid_w, rid_w;
  wire [  7:0] len_w;
  wire [ASB:0] adr_w;
  wire [CSB:0] cdata_w;

  assign s_tready = sready_w && cready_w && cyc_q;

  // -- Parser for Memory Transaction Requests -- //

  localparam [5:0] OP_IDLE = 6'b000001;
  localparam [5:0] OP_ADR0 = 6'b000010;
  localparam [5:0] OP_ADR1 = 6'b000100;
  localparam [5:0] OP_ADR2 = 6'b001000;
  localparam [5:0] OP_IDAD = 6'b010000;
  localparam [5:0] OP_BUSY = 6'b100000;

  reg [5:0] mop_q;
  reg [7:0] cnt_q;
  reg end_q;
  wire [8:0] dec_w = cnt_q - 1;

  always @(posedge bus_clock) begin
    if (bus_reset) begin
    end else begin
      case (state)
        ST_IDLE: begin
        end
        ST_SIZE: begin
        end
      endcase
    end
  end

  always @(posedge bus_clock) begin
    if (bus_reset) begin
      new_q <= 1'b0;
      cyc_q <= 1'b0;
      end_q <= 1'b0;
    end else if (!cyc_q && state == ST_IDLE && s_tvalid && s_tkeep) begin
      new_q <= 1'b1;
      cyc_q <= 1'b1;
      end_q <= 1'b0;
    end else begin
      new_q <= 1'b0;
      end_q <= s_tvalid && s_tready && dec_w == 9'd1;

      if (s_tvalid && s_tready && (dec_w == 9'd0 || s_tlast)) begin
        cyc_q <= 1'b0;
      end else begin
        cyc_q <= cyc_q;
      end
    end
  end

  always @(posedge bus_clock) begin
    if (bus_reset || stb_q && cready_w) begin
      stb_q <= 1'b0;
    end else if (mop_q == OP_IDAD) begin
      stb_q <= 1'b1;
    end
  end

  always @(posedge bus_clock) begin
    if (bus_reset) begin
      wen_q <= 1'b0;
    end else begin
      if (cmd_q[7] == 1'b0 && mop_q == OP_IDAD && state != ST_IDLE) begin
        wen_q <= 1'b1;
      end else if (s_tvalid && s_tready && (end_q || s_tlast)) begin
        wen_q <= 1'b0;
      end
    end
  end

  always @(posedge bus_clock) begin
    if (bus_reset) begin
      mop_q <= OP_IDLE;
      len_q <= 8'bx;
      cnt_q <= 8'd0;
      adr_q <= {ADDRESS_WIDTH{1'bx}};
      tid_q <= {ID_WIDTH{1'bx}};
    end else if (s_tvalid && s_tready) begin
      case (mop_q)
        OP_IDLE: begin
          len_q <= s_tdata;
          mop_q <= OP_ADR0;
        end
        OP_ADR0: begin
          adr_q[7:0] <= s_tdata;
          mop_q <= OP_ADR1;
        end
        OP_ADR1: begin
          adr_q[15:8] <= s_tdata;
          mop_q <= OP_ADR2;
        end
        OP_ADR2: begin
          adr_q[23:16] <= s_tdata;
          mop_q <= OP_IDAD;
        end
        OP_IDAD: begin
          {tid_q, adr_q[ASB:24]} <= s_tdata;
          cnt_q <= len_q;
          mop_q <= OP_BUSY;
        end
        OP_BUSY: begin
          mop_q <= mop_q;
          cnt_q <= dec_w[7:0];
        end
      endcase
    end else if (!cyc_q) begin
      mop_q <= OP_IDLE;
      cmd_q <= s_tdata;
    end
  end

  assign m_tkeep = m_tvalid;

  sync_fifo #(
      .OUTREG(3),  // 0, 1, 2, or 3
      .WIDTH (9),
      .ABITS (10)
  ) U_FIFO0 (
      .clock(bus_clock),
      .reset(bus_reset),

      .level_o(),

      .valid_i(vlq_q),
      .ready_o(rdy_w),
      .data_i (dat_q),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .data_o ({m_tlast, m_tdata})
  );


endmodule  /* reqsplit */
