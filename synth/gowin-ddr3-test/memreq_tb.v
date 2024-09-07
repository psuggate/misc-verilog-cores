`timescale 1ns / 100ps
module memreq_tb;

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

  reg [47:0] req = {CMD_STORE, 8'h08, 4'hA, 28'h0_20_80_F0};

  reg s_tvalid, s_tkeep, s_tlast, m_tready;
  reg [7:0] s_tdata;
  wire s_tready, m_tvalid, m_tkeep, m_tlast;
  wire [7:0] m_tdata;

  always #5 mclk <= ~mclk;
  always #8 bclk <= ~bclk;

  initial begin
    rst <= 1'b1;
    #40 rst <= 1'b0;

    #80 $finish;
  end


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
    .s_tkeep(s_tkeep),
    .s_tlast(s_tlast),
    .s_tdata(s_tdata),

    .m_tvalid(m_tvalid),
    .m_tready(m_tready),
    .m_tkeep(m_tkeep),
    .m_tlast(m_tlast),
    .m_tdata(m_tdata),

    .awvalid_o(),
    .awready_i(),
    .awaddr_o(),
    .awid_o(),
    .awlen_o(),
    .awburst_o(),

    .wvalid_o(),
    .wready_i(),
    .wlast_o(),
    .wstrb_o(),
    .wdata_o(),

    .bvalid_i(),
    .bready_o(),
    .bresp_i(),
    .bid_i(),

    .arvalid_o(),
    .arready_i(),
    .araddr_o(),
    .arid_o(),
    .arlen_o(),
    .arburst_o(),

    .rvalid_i(),
    .rready_o(),
    .rlast_i(),
    .rresp_i(),
    .rid_i(),
    .rdata_i()
);


endmodule  /* memreq_tb */
