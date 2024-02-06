`timescale 1ns / 100ps
/**
 * Converts simple memory-controller commands into DFI commands.
 * 
 * Notes:
 *  - assumes that the AXI4 interface converts write-data into 128-bit chunks,
 *    (written as 4x 32-bit sequential transfers) padding as required;
 *  - read data will also be a (continuous) stream of 128-bit chunks, so the
 *    AXI4 interface will have to drop any (unwanted) trailing data, if not
 *    required;
 *  - assumes that the memory controller and the AXI4 bus are within the same
 *    clock-domain;
 * 
 * Copyright 2023, Patrick Suggate.
 * 
 */
module gw2a_ddr3_phy (
    clock,
    reset,

    clk_ddr,

    dfi_cke_i,
    dfi_rst_ni,
    dfi_cs_ni,
    dfi_ras_ni,
    dfi_cas_ni,
    dfi_we_ni,
    dfi_odt_i,
    dfi_bank_i,
    dfi_addr_i,

    dfi_wstb_i,
    dfi_wren_i,
    dfi_mask_i,
    dfi_data_i,

    dfi_rden_i,
    dfi_rvld_o,
    dfi_last_o,
    dfi_data_o,

    ddr_ck_po,
    ddr_ck_no,
    ddr_cke_o,
    ddr_rst_no,
    ddr_cs_no,
    ddr_ras_no,
    ddr_cas_no,
    ddr_we_no,
    ddr_odt_o,
    ddr_ba_o,
    ddr_a_o,
    ddr_dm_o,
    ddr_dqs_pio,
    ddr_dqs_nio,
    ddr_dq_io
);

  parameter DDR3_WIDTH = 16;
  parameter DDR3_MASKS = DDR3_WIDTH / 8;

  localparam MSB = DDR3_WIDTH - 1;
  localparam QSB = DDR3_MASKS - 1;

  localparam DSB = DDR3_WIDTH + MSB;
  localparam SSB = DDR3_MASKS + QSB;

  parameter ADDR_BITS = 14;
  localparam ASB = ADDR_BITS - 1;

  parameter WR_PREFETCH = 1'b0;
  parameter CLOCK_SHIFT = 3'b100;


  input clock;
  input reset;

  input clk_ddr;  // Same phase, but twice freq of 'clock'

  input dfi_cke_i;
  input dfi_rst_ni;
  input dfi_cs_ni;
  input dfi_ras_ni;
  input dfi_cas_ni;
  input dfi_we_ni;
  input dfi_odt_i;

  input [2:0] dfi_bank_i;
  input [ASB:0] dfi_addr_i;

  input dfi_wstb_i;
  input dfi_wren_i;
  input [SSB:0] dfi_mask_i;
  input [DSB:0] dfi_data_i;

  input dfi_rden_i;
  output dfi_rvld_o;
  output dfi_last_o;
  output [DSB:0] dfi_data_o;

  output ddr_ck_po;
  output ddr_ck_no;
  output ddr_cke_o;
  output ddr_rst_no;
  output ddr_cs_no;
  output ddr_ras_no;
  output ddr_cas_no;
  output ddr_we_no;
  output ddr_odt_o;
  output [2:0] ddr_ba_o;
  output [ASB:0] ddr_a_o;
  output [QSB:0] ddr_dm_o;
  inout [QSB:0] ddr_dqs_pio;
  inout [QSB:0] ddr_dqs_nio;
  inout [MSB:0] ddr_dq_io;


  reg cke_q, rst_nq, cs_nq;
  reg ras_nq, cas_nq, we_nq, odt_q;
  reg [2:0] ba_q;

  reg delay_q, valid_q, last_q;
  reg  [ASB:0] addr_q;
  wire [SSB:0] mask_w;
  wire [DSB:0] data_w;


  // -- Write-Data Prefetch and Registering -- //

  generate
    if (WR_PREFETCH) begin : gen_wr_prefetch

      // Fetch the write -data & -masks a cycle earlier, so that an extra layer
      // of pipeline registers can be placed between the outputs of the FIFO's
      // and the IOB's.
      reg [SSB:0] mask_q;
      reg [DSB:0] data_q;

      assign mask_w = mask_q;
      assign data_w = data_q;

      always @(posedge clock) begin
        mask_q <= ~dfi_mask_i;
        data_q <= dfi_data_i;
      end

    end else begin : gen_no_prefetch

      // Connect the outputs of the FIFO's directly to the IOB's, even though
      // this will result in quite a lot of routing and combinational delay.
      assign mask_w = ~dfi_mask_i;
      assign data_w = dfi_data_i;

    end
  endgenerate


  // -- DFI Read-Data Signal Assignments -- //

  assign dfi_rvld_o = valid_q;
  assign dfi_last_o = last_q;


  // -- DDR3 Signal Assignments -- //

  assign ddr_ck_po  = ~clock;
  assign ddr_ck_no  = clock;

  assign ddr_cke_o  = cke_q;
  assign ddr_rst_no = rst_nq;
  assign ddr_cs_no  = cs_nq;
  assign ddr_ras_no = ras_nq;
  assign ddr_cas_no = cas_nq;
  assign ddr_we_no  = we_nq;
  assign ddr_odt_o  = odt_q;
  assign ddr_ba_o   = ba_q;
  assign ddr_a_o    = addr_q;


  // -- DDR3 Command Signals -- //

  always @(posedge clock) begin
    if (reset) begin
      cke_q  <= 1'b0;
      rst_nq <= 1'b0;
      cs_nq  <= 1'b1;
      ras_nq <= 1'b1;
      cas_nq <= 1'b1;
      we_nq  <= 1'b1;
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


  // -- Read Data Valid Signals -- //

  always @(posedge clock) begin
    if (reset) begin
      delay_q <= 1'b0;
      valid_q <= 1'b0;
      last_q  <= 1'b0;
    end else begin
      {valid_q, delay_q} <= {delay_q, dfi_rden_i};
      last_q <= delay_q & ~dfi_rden_i;
    end
  end


  // -- DDR3 Data Path IOBs -- //

  generate
    for (genvar ii = 0; ii < DDR3_WIDTH; ii++) begin : gen_dq_iobs

      gw2a_ddr_iob #(
          .SHIFT(CLOCK_SHIFT)
      ) u_gw2a_dq_iob (
          .PCLK(clock),
          .FCLK(~clk_ddr),
          .RESET(reset),
          .OEN(~dfi_wren_i),
          .D0(data_w[ii]),
          .D1(data_w[DDR3_WIDTH+ii]),
          .Q0(dfi_data_o[ii]),
          .Q1(dfi_data_o[DDR3_WIDTH+ii]),
          .IO(ddr_dq_io[ii])
      );

    end
  endgenerate


  // -- Write-Data Masks Outputs -- //

  generate
    for (genvar ii = 0; ii < DDR3_MASKS; ii++) begin : gen_dm_iobs

      ODDR u_gw2a_dm_oddr (
          .CLK(~clock),
          .TX (1'b0),
          .D0 (mask_w[ii]),
          .D1 (mask_w[DDR3_MASKS+ii]),
          .Q0 (ddr_dm_o[ii]),
          .Q1 ()
      );

    end
  endgenerate


  // -- Read- & Write- Data Strobes -- //

  wire dqs_w;

  assign dqs_w = ~dfi_wstb_i & ~dfi_wren_i;

  generate
    for (genvar ii = 0; ii < DDR3_MASKS; ii++) begin : gen_dqs_iobs

      gw2a_ddr_iob #(
          .SHIFT(CLOCK_SHIFT),
`ifdef __icarus
          .TLVDS(1'b1)
`else
          .TLVDS(1'b0)
`endif
      ) u_gw2a_dqs_iob (
          .PCLK(clock),
          .FCLK(clk_ddr),
          .RESET(reset),
          .OEN(dqs_w),
          .D0(1'b1),
          .D1(1'b0),
          .Q0(),
          .Q1(),
          .IO(ddr_dqs_pio[ii]),
          .IOB(ddr_dqs_nio[ii])
      );

    end
  endgenerate


endmodule  // gw2a_ddr3_phy
