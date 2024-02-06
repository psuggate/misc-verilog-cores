`timescale 1ns / 100ps
/**
 * Generic PHY -- that probably won't synthesise correctly, due to how the
 * (read-)data is registered ...
 *
 * Todo:
 *  - remove all of the shift-registers;
 *  - only instantiate IOB registers, and the minimum of other logic;
 *  - better method for registering the DQ inputs;
 */
module generic_ddr3_phy #(
    parameter DDR3_WIDTH = 16,
    parameter DDR3_MASKS = DDR3_WIDTH / 8,

    localparam MSB = DDR3_WIDTH - 1,
    localparam QSB = DDR3_MASKS - 1,

    localparam DSB = DDR3_WIDTH + MSB,
    localparam SSB = DDR3_MASKS + QSB,

    parameter ADDR_BITS = 14,
    localparam ASB = ADDR_BITS - 1
) (
    input clock,
    input reset,

    input clk_ddr,  // Same phase, but twice freq of 'clock'

    input dfi_cke_i,
    input dfi_rst_ni,
    input dfi_cs_ni,
    input dfi_ras_ni,
    input dfi_cas_ni,
    input dfi_we_ni,
    input dfi_odt_i,

    input [  2:0] dfi_bank_i,
    input [ASB:0] dfi_addr_i,

    input dfi_wstb_i,
    input dfi_wren_i,
    input [SSB:0] dfi_mask_i,
    input [DSB:0] dfi_data_i,

    input dfi_rden_i,
    output dfi_rvld_o,
    output dfi_last_o,
    output [DSB:0] dfi_data_o,

    output ddr3_ck_po,
    output ddr3_ck_no,
    output ddr3_cke_o,
    output ddr3_rst_no,
    output ddr3_cs_no,
    output ddr3_ras_no,
    output ddr3_cas_no,
    output ddr3_we_no,
    output ddr3_odt_o,
    output [2:0] ddr3_ba_o,
    output [ASB:0] ddr3_a_o,
    output [QSB:0] ddr3_dm_o,
    inout [QSB:0] ddr3_dqs_pio,
    inout [QSB:0] ddr3_dqs_nio,
    inout [MSB:0] ddr3_dq_io
);

  reg dqs_t, dq_t;
  wire [QSB:0] dqs_p, dqs_n;
  reg [QSB:0] dm_q;
  reg [MSB:0] dq_q;
  reg cke_q, rst_nq, cs_nq;
  reg ras_nq, cas_nq, we_nq, odt_q;
  reg [2:0] ba_q;

  reg valid_q, last_q;
  reg [ASB:0] addr_q;
  reg [DSB:0] data_q;


  // -- DFI Read-Data Signal Assignments -- //

  assign dfi_rvld_o   = valid_q;
  assign dfi_last_o   = last_q;
  assign dfi_data_o   = data_q;


  // -- DDR3 Signal Assignments -- //

  assign ddr3_ck_po   = ~clock;
  assign ddr3_ck_no   = clock;

  assign ddr3_cke_o   = cke_q;
  assign ddr3_rst_no  = rst_nq;
  assign ddr3_cs_no   = cs_nq;
  assign ddr3_ras_no  = ras_nq;
  assign ddr3_cas_no  = cas_nq;
  assign ddr3_we_no   = we_nq;
  assign ddr3_odt_o   = odt_q;
  assign ddr3_ba_o    = ba_q;
  assign ddr3_a_o     = addr_q;

  assign ddr3_dqs_pio = dqs_t ? {DDR3_MASKS{1'bz}} : dqs_p;
  assign ddr3_dqs_nio = dqs_t ? {DDR3_MASKS{1'bz}} : dqs_n;
  assign ddr3_dm_o    = dm_q;
  assign ddr3_dq_io   = dq_t ? {DDR3_WIDTH{1'bz}} : dq_q;


  // -- DDR3 Command Signals -- //

  // todo: polarities of the 'n' signals?
  always @(posedge clock) begin
    if (reset) begin
      cke_q  <= 1'b0;
      rst_nq <= 1'b0;
      cs_nq  <= 1'b1;  // todo: 1'b1 ??
      ras_nq <= 1'b0;  // todo: 1'b1 ??
      cas_nq <= 1'b0;  // todo: 1'b1 ??
      we_nq  <= 1'b0;  // todo: 1'b1 ??
      ba_q   <= 3'b0;
      addr_q <= {ADDR_BITS{1'b0}};
      odt_q  <= 1'b0;
    end else begin
      cke_q  <= dfi_cke_i;
      rst_nq <= dfi_rst_ni;
      cs_nq  <= dfi_cs_ni;
      ras_nq <= dfi_ras_ni;
      cas_nq <= dfi_cas_ni;
      we_nq  <= dfi_we_ni;
      odt_q  <= dfi_odt_i;
      ba_q   <= dfi_bank_i;
      addr_q <= dfi_addr_i;
    end
  end


  // -- DDR3 Data Strobes -- //

  wire dqs_w;

  assign dqs_w = ~dfi_wstb_i & ~dfi_wren_i;

  assign dqs_p = {DDR3_MASKS{~clock}};
  assign dqs_n = {DDR3_MASKS{clock}};

  always @(negedge clock) begin
    if (reset) begin
      dqs_t <= 1'b1;
    end else if (dfi_wstb_i) begin
      dqs_t <= 1'b0;
    end else begin
      dqs_t <= dqs_w;
    end
  end


  // -- Write-Data Outputs -- //

  reg hi_q;
  wire [MSB:0] dq_w;
  wire [QSB:0] dm_w;
  reg [MSB:0] dq_s;
  reg [QSB:0] dm_s;

  assign dm_w = ~dfi_mask_i[QSB:0];
  assign dq_w = dfi_data_i[MSB:0];

  always @(posedge clk_ddr) begin
    dm_s <= ~dfi_mask_i[SSB:DDR3_MASKS];
    dq_s <= dfi_data_i[DSB:DDR3_WIDTH];
  end

  always @(negedge clk_ddr) begin
    if (reset) begin
      dq_t <= 1'b1;
      hi_q <= 1'b0;
    end else begin
      dq_t <= ~dfi_wren_i;
      hi_q <= ~hi_q & dfi_wren_i;
    end
    dm_q <= hi_q ? dm_s : dm_w;
    dq_q <= hi_q ? dq_s : dq_w;
  end


  // -- Data Capture on Read -- //

  reg [MSB:0] data_l, data_n, data_h;
  reg delay_p, delay_q;
  reg  [1:0] count;
  wire [1:0] cnext;

  assign cnext = count + 1;

  always @(posedge clock) begin
    if (reset || !valid_q) begin
      count  <= 0;
      last_q <= 0;
    end else begin
      count  <= cnext;
      last_q <= cnext == 3;
    end
  end

  always @(posedge clock) begin
    {valid_q, delay_q, delay_p} <= {delay_q, delay_p, dfi_rden_i};
  end

  always @(posedge clock) begin
    data_l <= data_n;
    data_q <= {data_h, data_l};
  end

  always @(posedge ddr3_ck_po) begin
    if (ddr3_dqs_pio) begin
      data_n <= ddr3_dq_io;
    end
  end

  always @(posedge ddr3_ck_no) begin
    if (ddr3_dqs_nio) begin
      data_h <= ddr3_dq_io;
    end
  end


endmodule  // generic_ddr3_phy
