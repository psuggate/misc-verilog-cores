`timescale 1ns / 100ps
module axi_rd_path #(
    parameter  ADDRS = 32,
    localparam ASB   = ADDRS - 1,

    parameter  WIDTH = 32,
    localparam MSB   = WIDTH - 1,

    parameter  MASKS = WIDTH / 8,
    localparam SSB   = MASKS - 1,

    parameter AXI_ID_WIDTH = 4,
    localparam ISB = AXI_ID_WIDTH - 1,

    parameter CTRL_FIFO_DEPTH = 16,
    parameter CTRL_FIFO_BLOCK = 0,
    localparam CBITS = $clog2(CTRL_FIFO_DEPTH),

    parameter DATA_FIFO_DEPTH = 512,
    parameter DATA_FIFO_BLOCK = 1,
    localparam DBITS = $clog2(DATA_FIFO_DEPTH)
) (
    input clock,
    input reset,

    input axi_arvalid_i,  // AXI4 Read Address Port
    output axi_arready_o,
    input [ISB:0] axi_arid_i,
    input [7:0] axi_arlen_i,
    input [1:0] axi_arburst_i,
    input [ASB:0] axi_araddr_i,

    input axi_rready_i,  // AXI4 Read Data Port
    output axi_rvalid_o,
    output [MSB:0] axi_rdata_o,
    output [1:0] axi_rresp_o,
    output [ISB:0] axi_rid_o,
    output axi_rlast_o,

    output mem_fetch_o,
    input mem_accept_i,
    output mem_rseq_o,
    output [ISB:0] mem_reqid_o,
    output [ASB:0] mem_addr_o,

    input mem_valid_i,
    output mem_ready_o,
    input mem_last_i,
    input [ISB:0] mem_reqid_i,
    input [MSB:0] mem_data_i
);

  // -- Constants -- //

  localparam [1:0] BURST_INCR = 2'b01;
  localparam [1:0] AXI_RESP_OKAY = 2'b00;

  localparam COMMAND_WIDTH = ADDRS + AXI_ID_WIDTH + 1;

  // States for capturing read requests
  localparam ST_IDLE = 4'b0000;
  localparam ST_CHOP = 4'b0001;
  localparam ST_READ = 4'b0010;
  localparam ST_BUSY = 4'b0100;


  reg aready;
  reg [3:0] state;
  wire cmd_ready, rcf_valid, rdf_ready, rrf_ready;

  wire xvalid, xready, xseq;
  wire [ISB:0] xid;
  wire [ASB:0] xaddr;


  assign axi_arready_o = cmd_ready;
  assign axi_rresp_o   = rrf_ready ? AXI_RESP_OKAY : 2'bxx;

  assign mem_fetch_o   = rcf_valid;
  assign mem_ready_o   = rdf_ready;


  // -- Chunker for Large Bursts -- //

  axi_chunks #(
      .ADDRS(ADDRS),
      .REQID(AXI_ID_WIDTH)
  ) chunker_inst (
      .clock(clock),
      .reset(reset),

      .avalid_i(axi_arvalid_i & cmd_ready),
      .aready_o(cmd_ready),
      .alen_i(axi_arlen_i),
      .aburst_i(axi_arburst_i),
      .aid_i(axi_arid_i),
      .aaddr_i(axi_araddr_i),

      .xvalid_o(xvalid),
      .xready_i(xready),
      .xseq_o(xseq),
      .xid_o(xid),
      .xaddr_o(xaddr)
  );


  // -- Read-Data Command FIFO -- //

  // todo: the output 'data_o' is combinational/async (by default), which could
  //   become the critical-path, as a subsequent MUX is required to select the
  //   actual address-bits, from: {wr_row, wr_col, rd_row, rd_col, mode_val} ??
  sync_fifo #(
      .WIDTH (COMMAND_WIDTH),
      .ABITS (CBITS),
      .OUTREG(CTRL_FIFO_BLOCK)
  ) command_fifo_inst (
      .clock(clock),
      .reset(reset),

      .valid_i(xvalid),
      .ready_o(xready),
      .data_i ({xaddr, xid, xseq}),

      .valid_o(rcf_valid),
      .ready_i(mem_accept_i),
      .data_o ({mem_addr_o, mem_reqid_o, mem_rseq_o})
  );


  // -- Read-Data Response FIFO -- //

  // todo: should this be in 'ddr3_axi_ctrl', so that it can be used for both
  //   READ & WRITE operations ??
  // todo: there is another read-response FIFO in 'ddr3_axi_ctrl' already, to
  //   handle the actual AXI ID's, whereas this one stores the memory-ordering
  //   ID's -- combine these two FIFO's ??
  sync_fifo #(
      .WIDTH (AXI_ID_WIDTH),
      .ABITS (CBITS),
      .OUTREG(CTRL_FIFO_BLOCK)
  ) response_fifo_inst (
      .clock(clock),
      .reset(reset),

      .valid_i(mem_accept_i),
      .ready_o(),
      .data_i (mem_reqid_o),

      .valid_o(rrf_ready),
      .ready_i(axi_rvalid_o & axi_rready_i & axi_rlast_o),
      .data_o (axi_rid_o)
  );


  // -- Synchronous, 2 kB, Read-Data FIFO -- //

  // todo: use a packet FIFO, so we only bother the AXI bus when we have a full
  //   frame of data to transfer ??
  sync_fifo #(
      .WIDTH (WIDTH + 1),
      .ABITS (DBITS),
      .OUTREG(DATA_FIFO_BLOCK)
  ) rddata_fifo_inst (
      .clock(clock),
      .reset(reset),

      .valid_i(mem_valid_i),
      .ready_o(rdf_ready),
      .data_i ({mem_last_i, mem_data_i}), // todo: pad end of bursts ??

      .valid_o(axi_rvalid_o),
      .ready_i(axi_rready_i),
      .data_o ({axi_rlast_o, axi_rdata_o})
  );


`ifdef __icarus

  always @(posedge clock) begin
    if (reset);
    else begin
      if (axi_arvalid_i && axi_arburst_i != BURST_INCR) begin
        $error("%10t: Only 'INCR' READ bursts are supported", $time);
        $fatal;
      end
    end
  end

`endif /* __icarus */


endmodule  /* axi_rd_path */
