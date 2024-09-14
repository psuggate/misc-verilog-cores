`timescale 1ns / 100ps
/**
 * Converts AXI4 requests into simple memory-controller commands.
 *
 * Notes:
 *  - assumes that the AXI4 interface converts write-data into 128-bit chunks,
 *    padding as required;
 *  - read data will also be a (continuous) stream of 128-bit chunks, so the
 *    AXI4 interface will have to drop any (unwanted) trailing data, if not
 *    required;
 *  - assumes that the memory controller and the AXI4 bus are within the same
 *    clock-domain;
 *
 * Copyright 2023, Patrick Suggate.
 *
 */
module ddr3_axi_ctrl #(
    // Sets the number of (full-width) AXI4 transfers for a burst transaction
    // to/from the memory-controller
    parameter MEM_BURST_LEN = 4,

    // For people that want their lives to be difficult ...
    parameter AXI_USES_SIZE = 0,
    parameter AXI_UNALIGNED = 0,

    parameter AXI_ID_WIDTH = 4,
    localparam ISB = AXI_ID_WIDTH - 1,

    parameter MEM_ID_WIDTH = 4,
    localparam TSB = MEM_ID_WIDTH - 1,
    localparam TZERO = {MEM_ID_WIDTH{1'b0}},

    // Byte-address width, in bits -- lower bits will (typ) be ignored, and upper
    // bits may be ignored as well, if they lie outside of address-range
    parameter  ADDRS = 32,
    localparam ASB   = ADDRS - 1,

    // Should be one of: {8, 16, 32, 64, 128, 256, 512, 1024}
    parameter  WIDTH = 32,
    localparam MSB   = WIDTH - 1,

    parameter  MASKS = WIDTH / 8,
    localparam SSB   = MASKS - 1,

    parameter CTRL_FIFO_DEPTH = 16,
    parameter CTRL_FIFO_BLOCK = 0,  // Defaults to using LUT-SRAM's
    localparam CBITS = $clog2(CTRL_FIFO_DEPTH),

    parameter DATA_FIFO_BYPASS = 0,
    parameter DATA_FIFO_DEPTH = 512,  // Default: 2kB SRAM block
    parameter DATA_FIFO_BLOCK = 1,  // Defaults to using SRAM hard-IP blocks
    localparam DBITS = $clog2(DATA_FIFO_DEPTH),

    // Determines whether to wait for all of the write-data, before issuing a
    // write command.
    // Note: note required if upstream source is fast and reliable.
    parameter USE_PACKET_FIFOS = 1,

    // If the memory controller is idle (and both datapaths), send any request
    // straight to the memory-controller (if 'FAST_PATH_ENABLE == 1')
    // todo: this will require combinational outputs, limiting frequency ??
    parameter FAST_PATH_ENABLE = 1
) (
    input clock,
    input reset,

    input axi_awvalid_i,  // AXI4 Write Address Port
    output axi_awready_o,
    input [ASB:0] axi_awaddr_i,
    input [ISB:0] axi_awid_i,
    input [7:0] axi_awlen_i,
    input [2:0] axi_awsize_i,
    input [1:0] axi_awburst_i,
    input axi_wvalid_i,  // AXI4 Write Data Port
    output axi_wready_o,
    input [MSB:0] axi_wdata_i,
    input [SSB:0] axi_wstrb_i,
    input axi_wlast_i,
    output axi_bvalid_o,  // AXI4 Write Response
    input axi_bready_i,
    output [1:0] axi_bresp_o,
    output [ISB:0] axi_bid_o,

    input axi_arvalid_i,  // AXI4 Read Address Port
    output axi_arready_o,
    input [ASB:0] axi_araddr_i,
    input [ISB:0] axi_arid_i,
    input [7:0] axi_arlen_i,
    input [2:0] axi_arsize_i,
    input [1:0] axi_arburst_i,
    input axi_rready_i,  // AXI4 Read Data Port
    output axi_rvalid_o,
    output [MSB:0] axi_rdata_o,
    output [1:0] axi_rresp_o,
    output [ISB:0] axi_rid_o,
    output axi_rlast_o,

    // Write-request port (to controller)
    output mem_wrreq_o,
    input mem_wrack_i,
    input mem_wrerr_i,
    output mem_wrlst_o,
    output [TSB:0] mem_wrtid_o,
    output [ASB:0] mem_wradr_o,

    // Write-data port (to datapath)
    output mem_valid_o,
    input mem_ready_i,
    output mem_wlast_o,
    output [SSB:0] mem_wmask_o,
    output [MSB:0] mem_wdata_o,

    // Read-request port (to controller)
    output mem_rdreq_o,
    input mem_rdack_i,
    input mem_rderr_i,
    output mem_rdlst_o,
    output [TSB:0] mem_rdtid_o,
    output [ASB:0] mem_rdadr_o,

    // Read-data port (from datapath)
    input mem_valid_i,
    output mem_ready_o,
    input mem_rlast_i,
    input [MSB:0] mem_rdata_i
);

  // -- Constants -- //

  localparam [1:0] BURST_INCR = 2'b01;

  // todo: this is but a sketch ...
  localparam COMMAND_WIDTH = 4 + 1 + WIDTH;

  localparam ADDR_ZERO_BITS = $clog2(MASKS);

  localparam REQ_ID_WIDTH = MEM_ID_WIDTH + AXI_ID_WIDTH;
  localparam RSB = REQ_ID_WIDTH - 1;
  localparam RZERO = {REQ_ID_WIDTH{1'b0}};

  reg [TSB:0] req_id;
  wire wr_accept, wr_seq, rd_accept, rd_seq, issued, rd_finish;

  assign mem_wrlst_o = ~wr_seq;
  assign mem_rdlst_o = ~rd_seq;

  assign wr_accept = mem_wrreq_o & mem_wrack_i;
  assign rd_accept = mem_rdreq_o & mem_rdack_i;
  assign rd_finish = axi_rvalid_o & axi_rready_i & axi_rlast_o;

  assign issued = wr_accept | rd_accept;


  // -- Queue the AXI Requests by Arrival Ordering -- //

  always @(posedge clock) begin
    if (reset) begin
      req_id <= TZERO;
    end else if (issued) begin
      req_id <= req_id + 1;
    end else begin
      req_id <= req_id;
    end
  end


  // -- AXI Interface to Memory Controller for Write-Data -- //

  // Order-ID's are concatenated with AXI transaction ID's, so that relative
  // ordering of AXI transactions is known -- even though reads and writes may
  // be re-ordered by the scheduler.
  wire [RSB:0] wr_resp_id, wr_req_id, aw_req_id;

  assign aw_req_id   = {req_id, axi_awid_i};  // concatenated ID's
  assign mem_wrtid_o = wr_req_id[RSB:AXI_ID_WIDTH];  // Mem. ID subrange
  assign axi_bid_o   = wr_resp_id[ISB:0];  // AXI ID subrange

  axi_wr_path #(
      .ADDRS(ADDRS),
      .WIDTH(WIDTH),
      .MASKS(MASKS),
      .AXI_ID_WIDTH(REQ_ID_WIDTH),
      .CTRL_FIFO_DEPTH(CTRL_FIFO_DEPTH),
      .DATA_FIFO_BYPASS(DATA_FIFO_BYPASS),
      .DATA_FIFO_DEPTH(DATA_FIFO_DEPTH),
      .USE_SYNC_FIFO(0),
      .USE_PACKET_FIFOS(USE_PACKET_FIFOS)
  ) U_WR_PATH1 (
      .clock(clock),
      .reset(reset),

      .axi_awvalid_i(axi_awvalid_i),  // AXI4 Write Address Port
      .axi_awready_o(axi_awready_o),
      .axi_awid_i(aw_req_id),
      .axi_awlen_i(axi_awlen_i),
      .axi_awburst_i(axi_awburst_i),
      .axi_awaddr_i(axi_awaddr_i),

      .axi_wvalid_i(axi_wvalid_i),  // AXI4 Write Data Port
      .axi_wready_o(axi_wready_o),
      .axi_wlast_i (axi_wlast_i),
      .axi_wstrb_i (axi_wstrb_i),
      .axi_wdata_i (axi_wdata_i),

      .axi_bvalid_o(axi_bvalid_o),  // AXI4 Write Response Port
      .axi_bready_i(axi_bready_i),
      .axi_bid_o(wr_resp_id),
      .axi_bresp_o(axi_bresp_o),

      .mem_store_o (mem_wrreq_o),
      .mem_accept_i(mem_wrack_i),
      .mem_wseq_o  (wr_seq),
      .mem_wrid_o  (wr_req_id),
      .mem_addr_o  (mem_wradr_o),

      .mem_valid_o(mem_valid_o),
      .mem_ready_i(mem_ready_i),
      .mem_last_o (mem_wlast_o),
      .mem_strb_o (mem_wmask_o),
      .mem_data_o (mem_wdata_o)
  );


  // -- AXI Interface to Memory Controller for Read-Data -- //

  axi_rd_path #(
      .ADDRS(ADDRS),
      .WIDTH(WIDTH),
      .MASKS(MASKS),
      .AXI_ID_WIDTH(MEM_ID_WIDTH),
      .CTRL_FIFO_DEPTH(CTRL_FIFO_DEPTH),
      .DATA_FIFO_BYPASS(DATA_FIFO_BYPASS),
      .DATA_FIFO_DEPTH(DATA_FIFO_DEPTH)
  ) U_RD_PATH1 (
      .clock(clock),
      .reset(reset),

      .axi_arvalid_i(axi_arvalid_i),
      .axi_arready_o(axi_arready_o),
      .axi_arid_i(req_id),
      .axi_arlen_i(axi_arlen_i),
      .axi_arburst_i(axi_arburst_i),
      .axi_araddr_i(axi_araddr_i),

      .axi_rvalid_o(axi_rvalid_o),
      .axi_rready_i(axi_rready_i),
      .axi_rlast_o(axi_rlast_o),
      .axi_rresp_o(axi_rresp_o),
      .axi_rid_o(),  // not used
      .axi_rdata_o(axi_rdata_o),

      .mem_fetch_o (mem_rdreq_o),
      .mem_accept_i(mem_rdack_i),
      .mem_rseq_o  (rd_seq),
      .mem_reqid_o (mem_rdtid_o),
      .mem_addr_o  (mem_rdadr_o),

      .mem_valid_i(mem_valid_i),
      .mem_ready_o(mem_ready_o),
      .mem_last_i (mem_rlast_i),  // todo: ...
      .mem_reqid_i(TZERO),
      .mem_data_i (mem_rdata_i)
  );


  // -- AXI4 Read-Transaction Response FIFO -- //

  // Note: only memory-command ordering ID's are sent to the memory controller,
  //   so this FIFO pairs the correct AXI response ID's with completed AXI read
  //   transactions.
  sync_fifo #(
      .WIDTH (AXI_ID_WIDTH),
      .ABITS (CBITS),
      .OUTREG(CTRL_FIFO_BLOCK)
  ) U_RD_RESP1 (
      .clock(clock),
      .reset(reset),

      .valid_i(rd_accept),
      .ready_o(),
      .data_i (axi_arid_i),

      .valid_o(),
      .ready_i(rd_finish),
      .data_o (axi_rid_o)
  );


`ifdef __icarus
  //
  //  Simulation Configuation & Sanity Checks
  ///

  wire [7:0] rlanes = 1 << axi_arsize_i;
  wire [7:0] wlanes = 1 << axi_awsize_i;

  always @(posedge clock) begin
    if (reset);
    else begin
      if (axi_awvalid_i && axi_awburst_i != BURST_INCR) begin
        $error("%10t: Only 'INCR' WRITE bursts are supported", $time);
        $fatal;
      end
      if (axi_arvalid_i && axi_arburst_i != BURST_INCR) begin
        $error("%10t: Only 'INCR' READ bursts are supported", $time);
        $fatal;
      end
      if (AXI_USES_SIZE && axi_arvalid_i && rlanes != MASKS) begin
        $error("%10t: Data-width resizing not supported", $time);
        $fatal;
      end
      if (AXI_USES_SIZE && axi_awvalid_i && wlanes != MASKS) begin
        $error("%10t: Data-width resizing not supported", $time);
        $fatal;
      end
    end
  end

`endif  /* !__icarus */


endmodule  /* ddr3_axi_ctrl */
