`timescale 1ns / 100ps
module memreq_tb;

  `include "axi_defs.vh"

  localparam FIFO_DEPTH = 512;
  localparam DATA_WIDTH = 32;

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

    s_tdata = req[7:0];
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

    #800 $finish;
  end

  // -- Simulation Signals & Registers -- //

  localparam ST_IDLE = 0;
  localparam ST_DONE = 1;
  localparam ST_WDAT = 2;
  localparam ST_RESP = 3;

  reg bvalid;
  reg [1:0] bresp;
  reg [3:0] bid;
  wire bready_w, awvalid_w, wvalid_w, wlast_w;
  wire [3:0] awid_w;
  wire [7:0] awlen_w;

  reg [3:0] state;

  always @(posedge bclk) begin
    if (rst) begin
      state  <= ST_IDLE;
      bvalid <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (awvalid_w) begin
            state <= ST_WDAT;
            bid   <= awid_w;
          end
        end
        ST_WDAT: begin
          if (wvalid_w && wlast_w) begin
            state <= ST_RESP;
          end
        end
        ST_RESP: begin
          bvalid <= 1'b1;
          bresp  <= RESP_OKAY;
          if (bready_w) begin
            state <= ST_DONE;
          end
        end
        ST_DONE: begin
          bvalid <= 1'b0;
          bresp  <= 2'dx;
          state  <= ST_IDLE;
        end
        default: begin
          $error("Error: Invalid 'state' value: %d (instance %m)", state);
          $finish;
        end
      endcase
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

      .arvalid_o(),
      .arready_i(1'b0),
      .araddr_o(),
      .arid_o(),
      .arlen_o(),
      .arburst_o(),

      .rvalid_i(1'b0),
      .rready_o(),
      .rlast_i(),
      .rresp_i(),
      .rid_i(),
      .rdata_i()
  );


endmodule  /* memreq_tb */
