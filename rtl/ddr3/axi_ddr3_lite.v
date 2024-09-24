`timescale 1ns / 100ps
/**
 * DDR3 controller with a simple AXI4 interface, and an optional read-only AXI4-
 * style interface, for "fast-path reads" (though this latter inferface is not
 * yet working).
 *
 * Copyright 2023, Patrick Suggate.
 *
 */
module axi_ddr3_lite #(
    // Settings for DLL=off mode
    parameter DDR_FREQ_MHZ = 100,
    parameter DDR_CL = 6,
    parameter DDR_CWL = 6,
    parameter DDR_DLL_OFF = 1,

    // These additional delays depend on how many registers are in the data-output
    // and data-capture paths, of the DDR3 PHY being used.
    // Note: the 'gw2a_ddr3_phy' requires these to be '3'
    parameter PHY_WR_DELAY = 1,
    parameter PHY_RD_DELAY = 1,

    // Trims an additional clock-cycle of latency, if '1'
    parameter LOW_LATENCY = 1'b1,  // 0 or 1

    // Uses an the 'wr_strob' signal to clock out the WRITE data from the upstream
    // FIFO, when enabled (vs. the 'wr_ready' signal, which has one more cycle of
    // delay).
    // Note: the 'gw2a_ddr3_phy' requires this to be enabled
    parameter WR_PREFETCH = 1'b0,

    // Enables the (read-) bypass port
    parameter BYPASS_ENABLE = 1'b0,

    // Size of bursts from memory controller perspective
    parameter PHY_BURSTLEN = 4,

    // Address widths
    parameter DDR_ROW_BITS = 15,
    localparam RSB = DDR_ROW_BITS - 1,
    parameter DDR_COL_BITS = 10,
    localparam CSB = DDR_COL_BITS - 1,

    localparam ADDRS = DDR_ROW_BITS + DDR_COL_BITS + 4,  // todo ...
    localparam ASB = ADDRS - 1,  // todo ...

    localparam FSM_ADDRS = ADDRS - $clog2(AXI_DAT_BITS / DDR_DQ_WIDTH),
    localparam FSB = FSM_ADDRS - 1,
    localparam ADDRS_LSB = ADDRS - FSM_ADDRS,

    // Data-path widths
    parameter DDR_DQ_WIDTH = 16,
    parameter DDR_DM_WIDTH = 2,

    parameter PHY_DAT_BITS = DDR_DQ_WIDTH * 2,
    localparam MSB = PHY_DAT_BITS - 1,
    parameter PHY_STB_BITS = DDR_DM_WIDTH * 2,
    localparam SSB = PHY_STB_BITS - 1,

    // AXI4 interconnect properties
    parameter AXI_ID_WIDTH = 4,
    localparam ISB = AXI_ID_WIDTH - 1,

    parameter MEM_ID_WIDTH = 4,
    localparam TSB = AXI_ID_WIDTH - 1,

    // todo: ...
    localparam AXI_DAT_BITS = PHY_DAT_BITS,
    localparam AXI_STB_BITS = PHY_STB_BITS,

    // todo: ...
    parameter DFIFO_BYPASS = 0,
    localparam CTRL_FIFO_DEPTH = 16,
    localparam DATA_FIFO_DEPTH = 512,

    // Determines whether to wait for all of the write-data, before issuing a
    // write command.
    // Note: note required if upstream source is fast and reliable.
    parameter USE_PACKET_FIFOS = 1
) (
    input arst_n,

    input clock,
    input reset,

    output configured_o,

    // Memory-Controller AXI4 Interface
    input axi_awvalid_i,
    output axi_awready_o,
    input [ASB:0] axi_awaddr_i,
    input [ISB:0] axi_awid_i,
    input [7:0] axi_awlen_i,
    input [1:0] axi_awburst_i,

    input axi_wvalid_i,
    output axi_wready_o,
    input axi_wlast_i,
    input [SSB:0] axi_wstrb_i,
    input [MSB:0] axi_wdata_i,

    output axi_bvalid_o,
    input axi_bready_i,
    output [1:0] axi_bresp_o,
    output [ISB:0] axi_bid_o,

    input axi_arvalid_i,
    output axi_arready_o,
    input [ASB:0] axi_araddr_i,
    input [ISB:0] axi_arid_i,
    input [7:0] axi_arlen_i,
    input [1:0] axi_arburst_i,

    output axi_rvalid_o,
    input axi_rready_i,
    output axi_rlast_o,
    output [1:0] axi_rresp_o,
    output [ISB:0] axi_rid_o,
    output [MSB:0] axi_rdata_o,

    input byp_arvalid_i,  // [optional] fast-read port
    output byp_arready_o,
    input [ASB:0] byp_araddr_i,
    input [ISB:0] byp_arid_i,
    input [7:0] byp_arlen_i,
    input [1:0] byp_arburst_i,

    input byp_rready_i,
    output byp_rvalid_o,
    output byp_rlast_o,
    output [1:0] byp_rresp_o,
    output [ISB:0] byp_rid_o,
    output [MSB:0] byp_rdata_o,

    output dfi_align_o,
    input  dfi_calib_i,

    // DDR3 PHY-Interface Signals
    output dfi_rst_no,
    output dfi_cke_o,
    output dfi_cs_no,
    output dfi_ras_no,
    output dfi_cas_no,
    output dfi_we_no,
    output dfi_odt_o,
    output [2:0] dfi_bank_o,
    output [RSB:0] dfi_addr_o,
    output dfi_wstb_o,
    output dfi_wren_o,
    output [SSB:0] dfi_mask_o,
    output [MSB:0] dfi_data_o,
    output dfi_rden_o,
    input dfi_rvld_i,
    input dfi_last_i,
    input [MSB:0] dfi_data_i
);

  `include "axi_defs.vh"

  // -- Global Signals and State -- //

  reg en_q;

  // AXI <-> FSM signals
  wire fsm_wrreq, fsm_wrlst, fsm_wrack, fsm_wrerr;
  wire fsm_rdreq, fsm_rdlst, fsm_rdack, fsm_rderr;
  wire byp_rdreq, byp_rdack, byp_rderr;
  wire [TSB:0] fsm_wrtid, fsm_rdtid, byp_rdtid;
  wire [FSB:0] fsm_wradr, fsm_rdadr, byp_rdadr;

  // AXI <-> {FSM, DDL} signals
  wire wr_valid, wr_ready, wr_last;
  wire rd_valid, rd_ready, rd_last;
  wire [SSB:0] wr_mask;
  wire [MSB:0] wr_data, rd_data;

  wire ddl_run, ddl_req, ddl_seq, ddl_ref, ddl_rdy;
  wire [2:0] ddl_cmd, ddl_ba;
  wire [RSB:0] ddl_adr;

  wire cfg_req, cfg_run, cfg_rdy, cfg_ref;
  wire [2:0] cfg_cmd, cfg_ba;
  wire [RSB:0] cfg_adr;

  wire ctl_run, ctl_req, ctl_seq, ctl_rdy;
  wire [2:0] ctl_cmd, ctl_ba;
  wire [RSB:0] ctl_adr;

  wire by_valid, by_ready, by_last;
  wire [MSB:0] by_data;

  assign configured_o = en_q;

  always @(posedge clock) begin
    en_q <= ~reset & cfg_run;
  end

  // -- AXI Requests to DDR3 Requests -- //

  ddr3_axi_ctrl #(
      .ADDRS(FSM_ADDRS),
      .WIDTH(AXI_DAT_BITS),
      .MASKS(AXI_STB_BITS),
      .AXI_ID_WIDTH(AXI_ID_WIDTH),
      .MEM_ID_WIDTH(MEM_ID_WIDTH),
      .CTRL_FIFO_DEPTH(CTRL_FIFO_DEPTH),
      .DATA_FIFO_BYPASS(DFIFO_BYPASS),
      .DATA_FIFO_DEPTH(DATA_FIFO_DEPTH),
      .USE_PACKET_FIFOS(USE_PACKET_FIFOS)
  ) U_AXI_CTRL (
      .clock(clock),
      .reset(reset),

      .axi_awvalid_i(axi_awvalid_i),  // AXI4 Write Address Port
      .axi_awready_o(axi_awready_o),
      .axi_awid_i(axi_awid_i),
      .axi_awlen_i(axi_awlen_i),
      .axi_awburst_i(axi_awburst_i),
      .axi_awsize_i(BURST_SIZE_4B),
      .axi_awaddr_i(axi_awaddr_i[ASB:ADDRS_LSB]),

      .axi_wvalid_i(axi_wvalid_i),  // AXI4 Write Data Port
      .axi_wready_o(axi_wready_o),
      .axi_wlast_i (axi_wlast_i),
      .axi_wstrb_i (axi_wstrb_i),
      .axi_wdata_i (axi_wdata_i),

      .axi_bvalid_o(axi_bvalid_o),  // AXI4 Write Response Port
      .axi_bready_i(axi_bready_i),
      .axi_bid_o(axi_bid_o),
      .axi_bresp_o(axi_bresp_o),

      .axi_arvalid_i(axi_arvalid_i),
      .axi_arready_o(axi_arready_o),
      .axi_arid_i(axi_arid_i),
      .axi_arlen_i(axi_arlen_i),
      .axi_arburst_i(axi_arburst_i),
      .axi_arsize_i(BURST_SIZE_4B),
      .axi_araddr_i(axi_araddr_i[ASB:ADDRS_LSB]),

      .axi_rvalid_o(axi_rvalid_o),
      .axi_rready_i(axi_rready_i),
      .axi_rlast_o(axi_rlast_o),
      .axi_rresp_o(axi_rresp_o),
      .axi_rid_o(axi_rid_o),
      .axi_rdata_o(axi_rdata_o),

      .mem_wrreq_o(fsm_wrreq),  // WRITE requests to FSM
      .mem_wrack_i(fsm_wrack),
      .mem_wrerr_i(fsm_wrerr),
      .mem_wrlst_o(fsm_wrlst),
      .mem_wrtid_o(fsm_wrtid),
      .mem_wradr_o(fsm_wradr),

      .mem_valid_o(wr_valid),  // WRITE data to DFI
      .mem_ready_i(wr_ready),
      .mem_wlast_o(wr_last),
      .mem_wmask_o(wr_mask),
      .mem_wdata_o(wr_data),

      .mem_rdreq_o(fsm_rdreq),  // READ requests to FSM
      .mem_rdack_i(fsm_rdack),
      .mem_rderr_i(fsm_rderr),
      .mem_rdlst_o(fsm_rdlst),
      .mem_rdtid_o(fsm_rdtid),
      .mem_rdadr_o(fsm_rdadr),

      .mem_valid_i(rd_valid),  // READ data from DFI
      .mem_ready_o(rd_ready),
      .mem_rlast_i(rd_last),
      .mem_rdata_i(rd_data)
  );

  // -- DDR3 Memory Controller FSM -- //

  wire [4:0] fsm_state_w, fsm_snext_w;

  ddr3_fsm #(
      .DDR_ROW_BITS(DDR_ROW_BITS),
      .DDR_COL_BITS(DDR_COL_BITS),
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .ADDRS(FSM_ADDRS)
  ) U_DDR3_FSM (
      .arst_n(arst_n),

      .clock(clock),
      .reset(~en_q),

      .state_o(fsm_state_w),
      .snext_o(fsm_snext_w),

      .mem_wrreq_i(fsm_wrreq),  // Bus -> Controller requests
      .mem_wrlst_i(fsm_wrlst),
      .mem_wrack_o(fsm_wrack),
      .mem_wrerr_o(fsm_wrerr),
      .mem_wrtid_i(fsm_wrtid),
      .mem_wradr_i(fsm_wradr),

      .mem_rdreq_i(fsm_rdreq),
      .mem_rdlst_i(fsm_rdlst),
      .mem_rdack_o(fsm_rdack),
      .mem_rderr_o(fsm_rderr),
      .mem_rdtid_i(fsm_rdtid),
      .mem_rdadr_i(fsm_rdadr),

      .cfg_req_i(cfg_req),  // Configuration port
      .cfg_rdy_o(cfg_rdy),
      .cfg_cmd_i(cfg_cmd),
      .cfg_ba_i (cfg_ba),
      .cfg_adr_i(cfg_adr),

      .ddl_req_o(ddl_req),  // Controller <-> DFI
      .ddl_seq_o(ddl_seq),
      .ddl_rdy_i(ddl_rdy),
      .ddl_ref_i(ddl_ref),
      .ddl_cmd_o(ddl_cmd),
      .ddl_ba_o (ddl_ba),
      .ddl_adr_o(ddl_adr)
  );

`ifdef __use_crusty_old_bypass

  ddr3_bypass #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .DDR_ROW_BITS(DDR_ROW_BITS),
      .DDR_COL_BITS(DDR_COL_BITS),
      .WIDTH(AXI_DAT_BITS),
      .ADDRS(FSM_ADDRS),
      .REQID(AXI_ID_WIDTH),
      .BYPASS_ENABLE(BYPASS_ENABLE)
  ) U_BYPASS (
      .clock(clock),
      .reset(~en_q),

      .axi_arvalid_i(byp_arvalid_i),  // AXI4 fast-path, read-only port
      .axi_arready_o(byp_arready_o),
      .axi_araddr_i(byp_araddr_i[ASB:ADDRS_LSB]),
      .axi_arid_i(byp_arid_i),
      .axi_arlen_i(byp_arlen_i),
      .axi_arburst_i(byp_arburst_i),

      .axi_rready_i(byp_rready_i),
      .axi_rvalid_o(byp_rvalid_o),
      .axi_rlast_o(byp_rlast_o),
      .axi_rresp_o(byp_rresp_o),
      .axi_rid_o(byp_rid_o),
      .axi_rdata_o(byp_rdata_o),

      .ddl_rvalid_i(by_valid),  // DDL READ data-path
      .ddl_rready_o(by_ready),
      .ddl_rlast_i (by_last),
      .ddl_rdata_i (by_data),

      .byp_run_i(cfg_run),  // Connects to the DDL
      .byp_req_o(ctl_req),
      .byp_seq_o(ctl_seq),  // Todo ...
      .byp_ref_i(cfg_ref),
      .byp_rdy_i(ctl_rdy),
      .byp_cmd_o(ctl_cmd),
      .byp_ba_o (ctl_ba),
      .byp_adr_o(ctl_adr),

      .ctl_run_o(),  // Intercepts these memory controller -> DDL signals
      .ctl_req_i(ddl_req),
      .ctl_seq_i(ddl_seq),
      .ctl_ref_o(ddl_ref),
      .ctl_rdy_o(ddl_rdy),
      .ctl_cmd_i(ddl_cmd),
      .ctl_ba_i(ddl_ba),
      .ctl_adr_i(ddl_adr),

      .ctl_rvalid_o(rd_valid),  // READ data from DDL -> memory controller data-path
      .ctl_rready_i(rd_ready),
      .ctl_rlast_o (rd_last),
      .ctl_rdata_o (rd_data)
  );

`else  /* !__use_crusty_old_bypass */

  ddr3_fastpath #(
      .ROW_BITS(DDR_ROW_BITS),
      .COL_BITS(DDR_COL_BITS),
      .WIDTH(AXI_DAT_BITS),
      .ADDRS(FSM_ADDRS),
      .REQID(AXI_ID_WIDTH),
      .ENABLE(BYPASS_ENABLE)
  ) U_BYPASS (
      .clock(clock),
      .reset(~en_q),

      .axi_arvalid_i(byp_arvalid_i),  // AXI4 fast-path, read-only port
      .axi_arready_o(byp_arready_o),
      .axi_araddr_i(byp_araddr_i[ASB:ADDRS_LSB]),
      .axi_arid_i(byp_arid_i),
      .axi_arlen_i(byp_arlen_i),
      .axi_arburst_i(byp_arburst_i),

      .axi_rready_i(byp_rready_i),
      .axi_rvalid_o(byp_rvalid_o),
      .axi_rlast_o(byp_rlast_o),
      .axi_rresp_o(byp_rresp_o),
      .axi_rid_o(byp_rid_o),
      .axi_rdata_o(byp_rdata_o),

      .ddl_rvalid_i(by_valid),  // DDL READ data-path
      .ddl_rready_o(by_ready),
      .ddl_rlast_i (by_last),
      .ddl_rdata_i (by_data),

      .ddl_run_i(cfg_run),  // Connects to the DDL
      .ddl_req_o(ctl_req),
      .ddl_seq_o(ctl_seq),  // Todo ...
      .ddl_ref_i(cfg_ref),
      .ddl_rdy_i(ctl_rdy),
      .ddl_cmd_o(ctl_cmd),
      .ddl_ba_o (ctl_ba),
      .ddl_adr_o(ctl_adr),

      .ctl_run_o(),  // Intercepts these memory controller -> DDL signals
      .ctl_req_i(ddl_req),
      .ctl_seq_i(ddl_seq),
      .ctl_ref_o(ddl_ref),
      .ctl_rdy_o(ddl_rdy),
      .ctl_cmd_i(ddl_cmd),
      .ctl_ba_i(ddl_ba),
      .ctl_adr_i(ddl_adr),

      .ctl_rvalid_o(rd_valid),  // READ data from DDL -> memory controller data-path
      .ctl_rready_i(rd_ready),
      .ctl_rlast_o (rd_last),
      .ctl_rdata_o (rd_data)
  );

`endif /* !__use_crusty_old_bypass */

  // -- Coordinate with the DDR3 to PHY Interface -- //

  ddr3_ddl #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .DDR_ROW_BITS(DDR_ROW_BITS),
      .DDR_COL_BITS(DDR_COL_BITS),
      .PHY_WR_DELAY(PHY_WR_DELAY),
      .PHY_RD_DELAY(PHY_RD_DELAY),
      .WR_PREFETCH (WR_PREFETCH),
      .LOW_LATENCY (LOW_LATENCY),
      .DFI_DQ_WIDTH(PHY_DAT_BITS),
      .DFI_DM_WIDTH(PHY_STB_BITS)
  ) U_DDL1 (
      .clock(clock),
      .reset(reset),

      .ddr_cke_i(dfi_cke_o),
      .ddr_cs_ni(dfi_cs_no),

      .ctl_seq_i(1'b0),  // Todo ...
      .ctl_req_i(ctl_req),
      .ctl_rdy_o(ctl_rdy),
      .ctl_cmd_i(ctl_cmd),
      .ctl_ba_i(ctl_ba),
      .ctl_adr_i(ctl_adr),

      .mem_wvalid_i(wr_valid),
      .mem_wready_o(wr_ready),
      .mem_wlast_i (wr_last),
      .mem_wrmask_i(wr_mask),
      .mem_wrdata_i(wr_data),

      .mem_rvalid_o(by_valid),
      .mem_rready_i(by_ready),
      .mem_rlast_o (by_last),
      .mem_rddata_o(by_data),

      .dfi_ras_no(dfi_ras_no),
      .dfi_cas_no(dfi_cas_no),
      .dfi_we_no (dfi_we_no),
      .dfi_bank_o(dfi_bank_o),
      .dfi_addr_o(dfi_addr_o),
      .dfi_wstb_o(dfi_wstb_o),
      .dfi_wren_o(dfi_wren_o),
      .dfi_mask_o(dfi_mask_o),
      .dfi_data_o(dfi_data_o),
      .dfi_rden_o(dfi_rden_o),
      .dfi_rvld_i(dfi_rvld_i),
      .dfi_last_i(dfi_last_i),
      .dfi_data_i(dfi_data_i)
  );

  ddr3_cfg #(
      .DDR_FREQ_MHZ(DDR_FREQ_MHZ),
      .DDR_ROW_BITS(DDR_ROW_BITS)
  ) U_DDR3_CFG (
      .clock(clock),
      .reset(reset),

      .dfi_rst_no(dfi_rst_no),
      .dfi_cke_o (dfi_cke_o),
      .dfi_cs_no (dfi_cs_no),
      .dfi_odt_o (dfi_odt_o),

      .dfi_align_o(dfi_align_o),
      .dfi_calib_i(dfi_calib_i),

      .ctl_req_o(cfg_req),  // Memory controller signals
      .ctl_run_o(cfg_run),  // When initialisation has completed
      .ctl_rdy_i(cfg_rdy),
      .ctl_cmd_o(cfg_cmd),
      .ctl_ref_o(cfg_ref),
      .ctl_ba_o (cfg_ba),
      .ctl_adr_o(cfg_adr)
  );


endmodule  /* axi_ddr3_lite */
