`timescale 1ns / 100ps
module axi_chunks (
    clock,
    reset,

    avalid_i,
    aready_o,
    alen_i,
    aburst_i,
    aid_i,
    aaddr_i,

    xvalid_o,
    xready_i,
    xseq_o,
    xid_o,
    xaddr_o
);

  parameter ADDRS = 32;
  parameter ASB = ADDRS - 1;

  // The ratio of AXI bus-width to the bus-width of the chunks determines the
  // amount to increment the address, for each chunk.
  parameter AXI_WIDTH = 32;
  parameter OUT_WIDTH = 16;

  parameter CHUNK = 2;
  localparam CSB = 7 - CHUNK;
  localparam CHUNK_SIZE = 1 << (2 + $clog2(AXI_WIDTH) - $clog2(OUT_WIDTH));

  parameter REQID = 4;
  localparam ISB = REQID - 1;


  input clock;
  input reset;

  input avalid_i;
  output aready_o;
  input [7:0] alen_i;
  input [1:0] aburst_i;
  input [ISB:0] aid_i;
  input [ASB:0] aaddr_i;

  output xvalid_o;
  input xready_i;
  output xseq_o;
  output [ISB:0] xid_o;
  output [ASB:0] xaddr_o;


  reg busy_q;
  reg [ISB:0] trid_q;
  reg [ASB:0] addr_q;
  wire busy_w, wseq_w;
  wire [ISB:0] trid_w;
  wire [ASB:0] addr_w;

  wire [CSB:0] cnext;
  reg  [CSB:0] count;


  assign aready_o = !busy_q && xready_i;

  assign xvalid_o = busy_w;
  assign xseq_o = wseq_w;
  assign xid_o = trid_w;
  assign xaddr_o = addr_w;

  assign busy_w = avalid_i & xready_i | busy_q;
  assign trid_w = busy_q ? trid_q : aid_i;
  assign addr_w = busy_q ? addr_q : aaddr_i;

  assign wseq_w = (~busy_q & avalid_i & xready_i & alen_i[7:CHUNK] != 0) | cnext > 0;
  assign cnext = count > 0 ? count - 1 : count;


  always @(posedge clock) begin
    if (reset) begin
      busy_q <= 1'b0;
      trid_q <= {REQID{1'bx}};
      addr_q <= {ADDRS{1'bx}};
      count  <= 0;
    end else if (!busy_q && avalid_i && xready_i) begin
      busy_q <= alen_i[7:CHUNK] != 0;
      trid_q <= aid_i;
      addr_q <= aaddr_i + CHUNK_SIZE;
      count  <= alen_i[CSB:CHUNK];
    end else if (busy_q && xready_i) begin
      busy_q <= cnext > 0;
      trid_q <= trid_q;
      addr_q <= addr_q + CHUNK_SIZE;
      count  <= cnext;
    end
  end


endmodule  // axi_chunks
