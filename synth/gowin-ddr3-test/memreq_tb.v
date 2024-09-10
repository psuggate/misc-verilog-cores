`timescale 1ns / 100ps
module memreq_tb;

  `include "axi_defs.vh"

  localparam FIFO_DEPTH = 512;
  localparam DATA_WIDTH = 32;
  localparam MSB = DATA_WIDTH - 1;

  localparam [7:0] CMD_NOP = 8'h00;
  localparam [7:0] CMD_STORE = 8'h01;
  localparam [7:0] CMD_WDONE = 8'h02;
  localparam [7:0] CMD_WFAIL = 8'h03;
  localparam [7:0] CMD_FETCH = 8'h80;
  localparam [7:0] CMD_RDATA = 8'h81;
  localparam [7:0] CMD_RFAIL = 8'h82;

  reg mclk = 1;
  reg bclk = 1;
  reg rst;
  wire configured;

  reg [47:0] req = {4'hA, 28'h0_20_80_F0, 8'h08, CMD_STORE};

  reg s_tvalid, s_tkeep, s_tlast, m_tready;
  reg [7:0] s_tdata;
  wire s_tready, m_tvalid, m_tkeep, m_tlast;
  wire [7:0] m_tdata;

  always #5 mclk <= ~mclk;
  always #8 bclk <= ~bclk;

  initial begin
    $dumpfile("memreq_tb.vcd");
    $dumpvars;

    rst      = 1'b1;
    s_tvalid = 1'b0;
    s_tkeep  = 1'b0;
    s_tlast  = 1'b0;
    m_tready = 1'b0;
    #40 rst = 1'b0;
    #16 @(posedge bclk) #1;

    s_tdata  = req[7:0];
    s_tvalid = 1'b1;
    s_tkeep  = 1'b1;
    #16 s_tdata = req[15:8];
    #16 s_tdata = req[23:16];
    #16 s_tdata = req[31:24];
    #16 s_tdata = req[39:32];
    #16 s_tdata = req[47:40];

    #16 s_tdata = $urandom;
    #16 s_tdata = $urandom;
    #16 s_tdata = $urandom;
    #16 s_tdata = $urandom;
    #16 s_tdata = $urandom;
    #16 s_tdata = $urandom;
    #16 s_tdata = $urandom;
    #16 s_tdata = $urandom;
    s_tlast = 1'b1;
    #16 s_tvalid = 1'b0;
    s_tkeep = 1'b0;
    s_tlast = 1'b0;

    while (!m_tvalid) @(posedge bclk);

    req <= {4'h5, 28'h0_20_80_F0, 8'h08, CMD_FETCH};

    #16 s_tdata = req[7:0];
    s_tvalid = 1'b1;
    s_tkeep  = 1'b1;
    s_tlast  = 1'b0;
    #16 s_tdata = req[15:8];
    #16 s_tdata = req[23:16];
    #16 s_tdata = req[31:24];
    #16 s_tdata = req[39:32];
    #16 s_tdata = req[47:40];
    s_tlast = 1'b1;

    #16 s_tvalid = 1'b0;
    s_tkeep = 1'b0;
    s_tlast = 1'b0;

    while (!m_tvalid) @(posedge bclk);

    #800 $finish;
  end

  initial #2000 $finish;

  // -- Simulation Signals & Registers -- //

  localparam ST_IDLE = 0;
  localparam ST_DONE = 1;
  localparam ST_WDAT = 2;
  localparam ST_RESP = 3;
  localparam ST_RADR = 4;
  localparam ST_RDAT = 5;
  localparam ST_REND = 6;

  reg bvalid;
  reg [1:0] bresp;
  reg [3:0] bid, tid_q;
  wire bready_w, awvalid_w, wvalid_w, wlast_w, arvalid_w, rready_w;
  wire [3:0] awid_w, arid_w;
  wire [7:0] awlen_w, arlen_w;

  reg vld_q, lst_q;
  reg [1:0] res_q;
  reg [7:0] len_q;
  reg [MSB:0] dat_q;
  integer count;
  wire [31:0] cnext;

  reg [3:0] state;

  always @(posedge mclk) begin
    if (rst) begin
      state  <= ST_IDLE;
      bvalid <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (awvalid_w) begin
            $display("%8t: Address-WRITE Request ('%m')", $time);
            state <= ST_WDAT;
            bid   <= awid_w;
          end else if (arvalid_w) begin
            $display("%8t: Address-READ Request ('%m')", $time);
            state <= ST_RDAT;
          end
        end

        ST_WDAT: begin
          if (wvalid_w && wlast_w) begin
            $display("%8t: Write-DATA Received ('%m')", $time);
            state <= ST_RESP;
          end
        end

        ST_RESP: begin
          bvalid <= 1'b1;
          bresp  <= RESP_OKAY;
          if (bready_w) begin
            $display("%8t: Write-Response Sent ('%m')", $time);
            state <= ST_DONE;
          end
        end

        ST_DONE: begin
          bvalid <= 1'b0;
          bresp  <= 2'dx;
          state  <= ST_IDLE;
          $display("%8t: Write DONE, returning to IDLE ('%m')", $time);
        end

        ST_RDAT: begin
          state <= vld_q && lst_q && rready_w ? ST_REND : state;
        end

        ST_REND: begin
          state <= ST_IDLE;
          $display("%8t: Read DONE, returning to IDLE ('%m')", $time);
        end

        default: begin
          $error("%8t: Error: Invalid 'state' value: %d ('%m')", $time, state);
          $finish;
        end
      endcase
    end
  end

  always @(posedge bclk) begin
    if (rst) begin
      m_tready <= 1'b0;
    end else if (m_tvalid) begin
      m_tready <= ~(m_tready & m_tlast);
    end
  end

  assign cnext = count + 1;

  always @(posedge mclk) begin
    if (rst) begin
      vld_q <= 1'b0;
      lst_q <= 1'b0;
      count <= 0;
      len_q <= 8'd0;
    end else begin
      if (arvalid_w && state == ST_IDLE) begin
        len_q <= arlen_w;
        tid_q <= arid_w;
        lst_q <= 1'b0;
        res_q <= RESP_OKAY;
        dat_q <= $urandom;
      end

      if (count < len_q) begin
        vld_q <= 1'b1;
        if (rready_w) begin
          dat_q <= $urandom;
          lst_q <= cnext >= len_q;
          count <= cnext;
        end
      end else begin
        vld_q <= 1'b0;
        lst_q <= 1'b0;
        res_q <= 2'bx;
        tid_q <= 4'bx;
        dat_q <= 32'bx;
      end
    end
  end


  //
  //  Cores Under Nondestructive Testing
  ///

  memreq #(
      .FIFO_DEPTH(FIFO_DEPTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) U_REQ1 (
      .mem_clock(mclk),  // DDR3 controller domain
      .mem_reset(rst),

      .bus_clock(bclk),  // SPI or USB domain
      .bus_reset(rst),

      .s_tvalid(s_tvalid),
      .s_tready(s_tready),
      .s_tkeep (s_tkeep),
      .s_tlast (s_tlast),
      .s_tdata (s_tdata),

      .m_tvalid(m_tvalid),
      .m_tready(m_tready),
      .m_tkeep (m_tkeep),
      .m_tlast (m_tlast),
      .m_tdata (m_tdata),

      .awvalid_o(awvalid_w),
      .awready_i(1'b1),
      .awaddr_o(),
      .awid_o(awid_w),
      .awlen_o(awlen_w),
      .awburst_o(),

      .wvalid_o(wvalid_w),
      .wready_i(1'b1),
      .wlast_o (wlast_w),
      .wstrb_o (),
      .wdata_o (),

      .bvalid_i(bvalid),
      .bready_o(bready_w),
      .bresp_i(bresp),
      .bid_i(bid),

      .arvalid_o(arvalid_w),
      .arready_i(1'b1),
      .araddr_o(),
      .arid_o(arid_w),
      .arlen_o(arlen_w),
      .arburst_o(),

      .rvalid_i(vld_q),
      .rready_o(rready_w),
      .rlast_i(lst_q),
      .rresp_i(res_q),
      .rid_i(tid_q),
      .rdata_i(dat_q)
  );


endmodule  /* memreq_tb */
