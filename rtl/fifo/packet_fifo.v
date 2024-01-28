`timescale 1ns / 100ps
module packet_fifo (
    clock,
    reset,

    level_o,

    valid_i,
    ready_o,
    last_i,
    drop_i,
    data_i,

    valid_o,
    ready_i,
    last_o,
    data_o
);

  // Skid-buffer for the output data, so that registered-output SRAM's can be
  // used; e.g., Xilinx Block SRAMs, or GoWin BSRAMs.
  parameter OUTREG = 1;  // 0, 1, or 2

  parameter WIDTH = 8;
  localparam MSB = WIDTH - 1;

  parameter ABITS = 4;
  localparam DEPTH = 1 << ABITS;
  localparam ASB = ABITS - 1;
  localparam ADDRS = ABITS + 1;
  localparam AZERO = {ABITS{1'b0}};


  input clock;
  input reset;

  output [ASB:0] level_o;

  input valid_i;
  output ready_o;
  input last_i;
  input drop_i;
  input [MSB:0] data_i;

  output valid_o;
  input ready_i;
  output last_o;
  output [MSB:0] data_o;


  reg [WIDTH:0] sram[0:DEPTH-1];

  // Write-port signals
  reg wready;
  reg [ABITS:0] waddr;
  wire [ABITS:0] waddr_next;

  // Read-port signals
  reg rvalid;
  reg [ABITS:0] raddr;
  wire [ABITS:0] raddr_next;

  // Packet address signals
  reg [ABITS:0] paddr;

  // Transition signals
  reg [ASB:0] level_q;
  wire fetch_w, store_w, match_w, wfull_w, empty_w, reject_a, accept_a;
  wire [ABITS:0] level_w, waddr_w, raddr_w;

  // Optional extra stage of registers, so that block SRAMs can be used.
  reg xvalid, xlast;
  wire xready;
  reg [MSB:0] xdata;


  assign level_o = level_q;
  assign ready_o = wready;


  // -- FIFO Status Signals -- //

  wire wrfull_next = waddr_next[ASB:0] == raddr[ASB:0] && store_w && !fetch_w;
  wire wrfull_curr = match_w && waddr[ABITS] != raddr[ABITS] && fetch_w == store_w;

  wire rempty_next = raddr_next[ASB:0] == paddr[ASB:0] && fetch_w && !accept_a;
  wire rempty_curr = paddr == raddr && fetch_w == accept_a;

  assign accept_a = valid_i && wready && last_i && !drop_i;
  assign reject_a = drop_i;  // ??

  assign store_w = valid_i && wready;
  assign match_w = waddr[ASB:0] == raddr[ASB:0];
  assign wfull_w = wrfull_curr || wrfull_next;
  assign empty_w = rempty_curr || rempty_next;

  assign level_w = waddr_w[ASB:0] - raddr_w[ASB:0];
  assign waddr_w = store_w ? waddr_next : waddr;
  assign raddr_w = fetch_w ? raddr_next : raddr;


  // -- Write Port -- //

  assign waddr_next = waddr + 1;

  always @(posedge clock) begin
    if (reset) begin
      waddr  <= AZERO;
      wready <= 1'b0;
    end else begin
      wready <= ~wfull_w;

      if (reject_a) begin
        waddr <= paddr;
      end else if (store_w) begin
        sram[waddr[ASB:0]] <= {last_i, data_i};
        waddr <= waddr_next;
      end
    end
  end


  // -- Frame Pointer -- //

  always @(posedge clock) begin
    if (reset) begin
      paddr <= AZERO;
    end else if (accept_a) begin
      paddr <= waddr_next;
    end
  end


  // -- Read Port -- //

  assign raddr_next = raddr + 1;

  always @(posedge clock) begin
    if (reset) begin
      raddr  <= AZERO;
      rvalid <= 1'b0;
    end else begin
      rvalid <= ~empty_w;

      if (fetch_w) begin
        raddr <= raddr_next;
      end
    end
  end


  // -- FIFO Status -- //

  always @(posedge clock) begin
    if (reset) begin
      level_q <= AZERO;
    end else begin
      level_q <= level_w[ASB:0];
    end
  end


  // -- Output Register (OPTIONAL) -- //

  generate
    if (OUTREG == 0) begin : g_async

      wire [WIDTH:0] data_w = sram[raddr[ASB:0]];

      // Suitable for Xilinx Distributed SRAM's, and similar, with fast, async
      // reads.
      assign fetch_w = rvalid && ready_i;

      assign valid_o = rvalid;
      assign last_o  = data_w[WIDTH];
      assign data_o  = data_w[MSB:0];

    end // g_async
  else if (OUTREG > 0) begin : g_outregs

      assign fetch_w = rvalid && (xvalid && xready || !xvalid);

      always @(posedge clock) begin
        if (reset) begin
          xvalid <= 1'b0;
        end else begin
          if (fetch_w) begin
            xvalid <= 1'b1;
            {xlast, xdata} <= sram[raddr[ASB:0]];
          end else if (xvalid && xready) begin
            xvalid <= 1'b0;
          end
        end
      end

      axis_skid #(
          .WIDTH (WIDTH),
          .BYPASS(OUTREG > 1 ? 0 : 1)
      ) axis_skid_inst (
          .clock(clock),
          .reset(reset),

          .s_tvalid(xvalid),
          .s_tready(xready),
          .s_tlast (xlast),
          .s_tdata (xdata),

          .m_tvalid(valid_o),
          .m_tready(ready_i),
          .m_tlast (last_o),
          .m_tdata (data_o)
      );

    end  // g_outregs
  endgenerate


endmodule  // packet_fifo
