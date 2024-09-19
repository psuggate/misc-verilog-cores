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
module gw2a_ddr3_phy #(
    parameter DDR3_WIDTH = 16,
    parameter DDR3_MASKS = DDR3_WIDTH / 8,

    localparam MSB = DDR3_WIDTH - 1,
    localparam QSB = DDR3_MASKS - 1,

    localparam DSB = DDR3_WIDTH + MSB,
    localparam SSB = DDR3_MASKS + QSB,

    parameter ADDR_BITS = 14,
    localparam ASB = ADDR_BITS - 1,

    parameter INVERT_MCLK = 0,
    parameter INVERT_DCLK = 0,
    parameter READ_CALIB  = 1,
    parameter WR_PREFETCH = 1'b0,
    parameter WRITE_DELAY = 2'b00,
    parameter CLOCK_SHIFT = 2'b10
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

    // For WRITE- & READ- CALIBRATION
    input dfi_align_i,
    output dfi_calib_o,
    output [2:0] dfi_shift_o,

    output ddr_ck_po,
    output ddr_ck_no,
    output ddr_cke_o,
    output ddr_rst_no,
    output ddr_cs_no,
    output ddr_ras_no,
    output ddr_cas_no,
    output ddr_we_no,
    output ddr_odt_o,
    output [2:0] ddr_ba_o,
    output [ASB:0] ddr_a_o,
    output [QSB:0] ddr_dm_o,
    inout [QSB:0] ddr_dqs_pio,
    inout [QSB:0] ddr_dqs_nio,
    inout [MSB:0] ddr_dq_io
);

`ifdef __icarus
  // The GoWin GW2A TLVDS instance is not directly available/visible, for the
  // DQS/DQS# signals, but we use them in simulations.
  localparam USE_TLVDS = 1'b1;
`else  /* !__icarus */
  localparam USE_TLVDS = 1'b0;
`endif  /* !__icarus */

  // -- DDR3 PHY State & Signals -- //

  reg cke_q, rst_nq, cs_nq;
  reg ras_nq, cas_nq, we_nq, odt_q;
  reg [2:0] ba_q;

  reg delay_q, valid_q, last_q;
  reg  [ASB:0] addr_q;
  wire [SSB:0] mask_w;
  wire [DSB:0] data_w;

  reg cyc_q, cal_q;
  reg [3:0] cnt_q;
  reg [2:0] rdcal;

  assign dfi_calib_o = cnt_q[3];
  assign dfi_shift_o = rdcal;

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

  assign ddr_ck_po  = INVERT_MCLK ? clock : ~clock;
  assign ddr_ck_no  = INVERT_MCLK ? ~clock : clock;

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

  // -- IOBs for the DDR3 Data Paths & Write-Data Masks -- //

  wire [MSB:0] wdat_lo_w, wdat_hi_w, rdat_lo_w, rdat_hi_w;
  wire [QSB:0] mask_hi_w, mask_lo_w, dm_w, en_w;

  assign {mask_hi_w, mask_lo_w} = mask_w;
  assign dfi_data_o = {rdat_hi_w, rdat_lo_w};
  assign {wdat_hi_w, wdat_lo_w} = data_w;

`ifdef __scared_of_snakes_on_planes

  ODDR u_gw2a_dm_oddr[QSB:0] (
      .CLK(~clock),
      .TX (1'b0),
      .D0 (mask_lo_w),
      .D1 (mask_hi_w),
      .Q0 (ddr_dm_o),
      .Q1 ()
  );

`else  /* !__scared_of_snakes_on_planes */

  OSER4 u_gw2a_dm_oddr[QSB:0] (
      .PCLK(clock),
      .FCLK(INVERT_DCLK ? ~clk_ddr : clk_ddr),
      .RESET(reset),
      .TX0(~dfi_wren_i),
      .TX1(~dfi_wren_i),
      .D0(mask_lo_w),
      .D1(mask_lo_w),
      .D2(mask_hi_w),
      .D3(mask_hi_w),
      .Q0(ddr_dm_o),
      .Q1()
  );

`endif  /* !__scared_of_snakes_on_planes */

  gw2a_ddr_iob #(
      .WRDLY(2'd0)
  ) u_gw2a_dq_iob[MSB:0] (
      .PCLK(clock),
      .FCLK(INVERT_DCLK ? ~clk_ddr : clk_ddr),
      .RESET(reset),
      .OEN(~dfi_wren_i),
      .SHIFT(READ_CALIB ? rdcal[1:0] : CLOCK_SHIFT),
      .D0(wdat_lo_w),
      .D1(wdat_hi_w),
      .Q0(rdat_lo_w),
      .Q1(rdat_hi_w),
      .IO(ddr_dq_io)
  );

  // -- Read- & Write- Data Strobes -- //

  wire dqs_w;
  wire [QSB:0] dqs_pw, dqs_nw;

  assign dqs_w = ~dfi_wstb_i & ~dfi_wren_i;

  gw2a_ddr_iob #(
      .WRDLY(WRITE_DELAY),
      .TLVDS(USE_TLVDS)
  ) u_gw2a_dqs_iob[QSB:0] (
      .PCLK(clock),
      .FCLK(INVERT_DCLK ? ~clk_ddr : clk_ddr),
      .RESET(reset),
      .OEN(dqs_w),
      .SHIFT(READ_CALIB ? rdcal[1:0] : CLOCK_SHIFT),
      .D0(1'b1),
      .D1(1'b0),
      .Q0(dqs_pw),
      .Q1(dqs_nw),
      .IO(ddr_dqs_pio),
      .IOB(ddr_dqs_nio)
  );

  // -- WRITE- & READ- CALIBRATION -- //

  reg rcv_q, err_q;
  reg [2:0] pat_q;
  reg [1:0] wcal, pre_q;
  wire error_w;
  wire [3:0] preamble_w;

  assign preamble_w = {dqs_nw[0], dqs_pw[0], pre_q};
  assign error_w = (^dqs_nw) | (^dqs_pw);

  always @(posedge clock) begin
    if (reset || !cyc_q) begin
      rcv_q <= 1'b0;
      err_q <= 1'b0;
    end else if (cyc_q) begin
      rcv_q <= pat_q == 3'd2 && !err_q;
      err_q <= pat_q != 3'd2 || err_q || error_w;
    end

    if (reset || err_q) begin
      cnt_q <= 4'd0;
    end else if (rcv_q && !cyc_q && !cnt_q[3]) begin
      cnt_q <= cnt_q + 1;
    end

    if (reset) begin
      cyc_q <= 1'b0;
      cal_q <= 1'b0;
      rdcal <= {1'b0, CLOCK_SHIFT};
    end else begin
      cyc_q <= valid_q;
      if (!cyc_q && err_q) begin
        // Rx. error occurred, so advance the clock-shift value
        rdcal <= rdcal + 1;
      end
    end

    pre_q <= preamble_w[3:2];  // Todo ...
    pat_q <= preamble_w[3:1];
  end

endmodule  /* gw2a_ddr3_phy */
