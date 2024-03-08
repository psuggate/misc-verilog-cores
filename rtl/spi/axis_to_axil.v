`timescale 1ns / 100ps
module axis_to_axil #(
                      // AXI-Lite settings
    parameter AXIL_DATA_BITS = 0,
                      localparam MSB = AXIL_DATA_BITS - 1,
                      localparam SSB = AXIL_DATA_BITS / 8 - 1,
    parameter AXIL_ID_BITS = 0,
                      localparam ISB = AXIL_ID_BITS - 1,
    parameter AXIL_ADDR_BITS = 0,
                      localparam ASB = AXIL_ADDR_BITS - 1
) (
    input clock,
    input reset,

   // Data to send (via SPI)
    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [7:0] s_tdata,

   // Data arriving (via SPI)
    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [7:0] m_tdata,

   // Interface to the AXI-L interconnect
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
    output [MSB:0] axi_rdata_o
);

  // -- Signals & State -- //


  // -- Parser for Control Transfer Parameters -- //

  always @(posedge clock) begin
  end


  // -- Main FSM -- //

  localparam [3:0] ST_IDLE = 4'h0, ST_TYPE = 4'h1, ST_ADDR = 4'h2, ST_WAIT = 4'h3, ST_SEND = 4'h4, ST_RECV = 4'h5, ST_RESP = 4'h6;

  reg [3:0] state;

  always @(posedge clock) begin
    if (reset) begin
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE: begin
        end
        default: begin
        end
      endcase
    end
  end


endmodule  // axis_to_axil
