`timescale 1ns / 100ps
/**
 * Write datapath, for an AXI4 to SDRAM interface.
 * 
 * For every WRITE-request, store one write command for each BL8 transaction
 * that is required to complete an AXI4 (burst-) WRITE request. The WRITE-data
 * FIFO stores all (burst-)data as one write-data packet.
 *
 * Note: WRITE-data buffering is used, so the AXI4 interface may accept multiple
 * packets before any are actually written to the SDRAM.
 * 
 * Copyright 2023, Patrick Suggate.
 * 
 */
module axi_wr_path (
    clock,
    reset,

    axi_awvalid_i,
    axi_awready_o,
    axi_awaddr_i,
    axi_awid_i,
    axi_awlen_i,
    axi_awburst_i,

    axi_wvalid_i,
    axi_wready_o,
    axi_wlast_i,
    axi_wstrb_i,
    axi_wdata_i,

    axi_bvalid_o,
    axi_bready_i,
    axi_bresp_o,
    axi_bid_o,

    mem_store_o,
    mem_accept_i,
    mem_wseq_o,
    mem_wrid_o,
    mem_addr_o,

    mem_valid_o,
    mem_ready_i,
    mem_last_o,
    mem_strb_o,
    mem_data_o
);

  parameter ADDRS = 32;
  localparam ASB = ADDRS - 1;

  parameter WIDTH = 32;
  localparam MSB = WIDTH - 1;

  parameter MASKS = WIDTH / 8;
  localparam SSB = MASKS - 1;

  parameter AXI_ID_WIDTH = 4;
  localparam ISB = AXI_ID_WIDTH - 1;

  parameter CTRL_FIFO_DEPTH = 16;
  parameter CTRL_FIFO_BLOCK = 0;
  localparam CBITS = $clog2(CTRL_FIFO_DEPTH);

  parameter DATA_FIFO_DEPTH = 512;
  parameter DATA_FIFO_BLOCK = 1;
  localparam DBITS = $clog2(DATA_FIFO_DEPTH);


  input clock;
  input reset;

  input axi_awvalid_i;  // AXI4 Write Address Port
  output axi_awready_o;
  input [ASB:0] axi_awaddr_i;
  input [ISB:0] axi_awid_i;
  input [7:0] axi_awlen_i;
  input [1:0] axi_awburst_i;
  input axi_wvalid_i;  // AXI4 Write Data Port
  output axi_wready_o;
  input [MSB:0] axi_wdata_i;
  input [SSB:0] axi_wstrb_i;
  input axi_wlast_i;
  output axi_bvalid_o;  // AXI4 Write Response
  input axi_bready_i;
  output [1:0] axi_bresp_o;
  output [ISB:0] axi_bid_o;

  output mem_store_o;
  input mem_accept_i;
  output mem_wseq_o;
  output [ISB:0] mem_wrid_o;
  output [ASB:0] mem_addr_o;

  output mem_valid_o;
  input mem_ready_i;
  output mem_last_o;
  output [SSB:0] mem_strb_o;
  output [MSB:0] mem_data_o;


  // todo:
  //  - padding with empty-words for unaligned and/or small transfers
  //  - any advantage to accepting commands _before_ data ??


  // -- Constants -- //

  localparam [1:0] BURST_INCR = 2'b01;
  localparam [1:0] AXI_RESP_OKAY = 2'b00;

  // Bit-width of the command-info that is stored in the WR-command FIFO
  localparam COMMAND_WIDTH = ADDRS + AXI_ID_WIDTH + 1;
  localparam WSB = COMMAND_WIDTH - 1;

  // States for capturing write requests
  localparam ST_IDLE = 4'b0000;
  localparam ST_FILL = 4'b0001;
  localparam ST_BUSY = 4'b0010;


  reg bvalid, aready, wready;
  reg [  3:0] state;
  reg [  1:0] bresp;
  reg [ISB:0] bwrid;

  wire wdf_ready, wdf_valid, wdf_last;
  wire cmd_ready, cmd_valid, wcf_valid;
  wire [WSB:0] command_w;

  wire xvalid, xready, xseq;
  wire [ISB:0] xid;
  wire [ASB:0] xaddr;


  assign axi_awready_o = aready;
  assign axi_wready_o = wready;
  assign axi_bvalid_o = bvalid;
  assign axi_bresp_o = bresp;
  assign axi_bid_o = bwrid;

  assign mem_store_o = wcf_valid;
  assign mem_valid_o = wdf_valid;
  assign mem_last_o = wdf_last;

  // Command- & data- FIFO signals
  assign cmd_valid = axi_awvalid_i & aready;
  assign command_w = {axi_awaddr_i, axi_awid_i};


  // -- FSM to Capture WRITE Requests and Data -- //

  always @(posedge clock) begin
    if (reset) begin
      state  <= ST_IDLE;
      aready <= 1'b0;
      wready <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          // Wait for incoming write-data requests
          if (cmd_valid) begin
            state  <= ST_FILL;
            aready <= 1'b0;
            wready <= 1'b1;
          end else begin
            state  <= ST_IDLE;
            aready <= 1'b1;
            wready <= 1'b0;
          end
        end

        ST_FILL: begin
          aready <= 1'b0;

          // Wait for the write-data to be stored
          if (axi_wvalid_i && wready && axi_wlast_i) begin
            wready <= 1'b0;
            if (!cmd_ready || !wdf_ready) begin
              state <= ST_BUSY;
            end else begin
              state <= ST_IDLE;
            end
          end else begin
            state  <= ST_FILL;
            wready <= 1'b1;
          end
        end

        ST_BUSY: begin
          // If either FIFO fills up, then wait for a bit
          if (cmd_ready && wdf_ready) begin
            state  <= ST_IDLE;
            aready <= 1'b1;
          end else begin
            state  <= ST_BUSY;
            aready <= 1'b0;
          end
          wready <= 1'b0;
        end

        default: begin
          $error("%10t: WRITE data state-machine failure!", $time);
          state  <= ST_IDLE;
          aready <= 1'b0;
          wready <= 1'b0;
          // $fatal;
        end
      endcase  // state
    end
  end


  // -- AXI WRITE-Response Logic -- //

  always @(posedge clock) begin
    if (reset) begin
      bvalid <= 1'b0;
      bresp  <= AXI_RESP_OKAY;
      bwrid  <= 'bx;
    end else begin
      bresp <= AXI_RESP_OKAY;

      if (mem_accept_i && !mem_wseq_o) begin
        bwrid <= mem_wrid_o;
      end else begin
        bwrid <= bwrid;
      end

      if (mem_ready_i && wdf_valid && wdf_last) begin
        bvalid <= 1'b1;
      end else if (bvalid && axi_bready_i) begin
        bvalid <= 1'b0;
      end
    end
  end


  // -- Chunker for Large Bursts -- //

  axi_chunks #(
      .ADDRS(ADDRS),
      .REQID(AXI_ID_WIDTH)
  ) chunker_inst (
      .clock(clock),
      .reset(reset),

      .avalid_i(axi_awvalid_i & aready),
      .aready_o(cmd_ready),
      .alen_i(axi_awlen_i),
      .aburst_i(axi_awburst_i),
      .aid_i(axi_awid_i),
      .aaddr_i(axi_awaddr_i),

      .xvalid_o(xvalid),
      .xready_i(xready),
      .xseq_o(xseq),
      .xid_o(xid),
      .xaddr_o(xaddr)
  );


  // -- Write-Data Command FIFO -- //

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

      .valid_o(wcf_valid),
      .ready_i(mem_accept_i),
      .data_o ({mem_addr_o, mem_wrid_o, mem_wseq_o})
  );


  // -- Synchronous, 2 kB, Write-Data FIFO -- //

  packet_fifo #(
      .WIDTH (MASKS + WIDTH),
      .ABITS (DBITS),
      .OUTREG(DATA_FIFO_BLOCK)
  ) wrdata_fifo_inst (
      .clock(clock),
      .reset(reset),

      .valid_i(axi_wvalid_i & wready),
      .ready_o(wdf_ready),
      .last_i (axi_wlast_i),
      .drop_i (1'b0),
      .data_i ({axi_wstrb_i, axi_wdata_i}), // todo: pad end of bursts ??

      .valid_o(wdf_valid),
      .ready_i(mem_ready_i),
      .last_o (wdf_last),
      .data_o ({mem_strb_o, mem_data_o})
  );


  // -- More Simulation Assertions -- //

`ifdef __icarus
  always @(posedge clock) begin
    if (reset);
    else begin
      if (axi_awvalid_i && axi_awburst_i != BURST_INCR) begin
        $error("%10t: Only 'INCR' WRITE bursts are supported", $time);
        $fatal;
      end

      // todo: temporary restrictions ...
      if (axi_awvalid_i && axi_awlen_i[1:0] != 2'd3) begin
        $error("%10t: Only WRITE bursts that are multiples of 16-bytes are supported", $time);
        $fatal;
      end
      if (axi_awvalid_i && axi_awaddr_i[2:0] != 3'd0) begin
        $error("%10t: Only 16-byte-aligned WRITE bursts are supported", $time);
        $fatal;
      end
      // odot: temporary restrictions ...
    end
  end
`endif


endmodule  // axi_wr_path
