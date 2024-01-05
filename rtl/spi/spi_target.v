`timescale 1ns / 100ps
module spi_target (
    input clock,
    input reset,

    input [6:0] status_i,

    // Error flags from the SPI link- & phy- layer
    output overflow_o,
    output underrun_o,

    // AXI4-Stream datapath for Target -> Master transfers
    input s_tvalid,
    output s_tready,
    input s_tlast,
    input [7:0] s_tdata,

    // AXI4-Stream datapath for Master -> Target transfers
    output m_tvalid,
    input m_tready,
    output m_tlast,
    output [7:0] m_tdata,

    input  SCK_pin,
    input  SSEL,
    input  MOSI,
    output MISO
);

  // -- Constants -- //

  parameter [7:0] HEADER = 8'ha7;

  parameter integer BYTES = 16;  // FIFO size
  localparam integer FSIZE = $clog2(BYTES);


  // FSM states:
  localparam [3:0] ST_IDLE = 4'h1;
  localparam [3:0] ST_XFER = 4'h2;
  localparam [3:0] ST_FILL = 4'h8;


  // -- State & Wires -- //

  reg [3:0] state;
  wire cycle, fetch, valid, empty, ready;
  wire [7:0] tdata, rdata;


  // -- I/O Assignments -- //

  assign valid = fetch && (state == ST_FILL || s_tvalid);
  assign s_tready = fetch;
  assign tdata = state == ST_FILL ? status_i : s_tdata;

  assign m_tvalid = ~empty;
  assign ready = m_tready & ~empty;
  assign m_tlast = 1'b0;  // todo: possible ??
  assign m_tdata = rdata;


  // -- SPI Transaction FSM -- //

  /**
   * Determine the type of SPI-transfer:
   *  - read-only (settings, raw-data, or visibilities);
   *  - read/write (settings, or raw-data); or
   *  - write-only (settings, or raw-data),
   * and then control the transfer until completion.
   */
  always @(posedge clock) begin
    if (reset) begin
      state <= ST_FILL;
    end else begin
      case (state)
        ST_FILL: begin
          // "Prime" the Tx FIFO with the status-byte
          state <= fetch ? ST_IDLE : state;
          // valid <= 1'b1;
        end

        ST_IDLE: begin
          // Wait/idle for the first Rx byte
          if (cycle && !empty) begin
            state <= ST_XFER;
          end
        end

        ST_XFER: begin
          if (!cycle && empty) begin
            state <= ST_FILL;
          end
        end
      endcase
    end
  end


  //-------------------------------------------------------------------------
  //  SPI-layer, and the domain-crossing subcircuits, of the interface.
  //-------------------------------------------------------------------------
  spi_layer #(
      .WIDTH(8),
      .FSIZE(FSIZE),
      .HEADER_BYTE(HEADER)
  ) ST_LAYER0 (
      .clk_i(clock),
      .rst_i(reset),

      .cyc_o(cycle),  // Transfer-cycle active

      .get_o(fetch),  // Slave -> Master datapath
      .rdy_i(valid),
      .dat_i(tdata),

      .wat_o(empty),  // Wait until Rx. FIFO has data
      .ack_i(ready),  // Master -> Slave datapath
      .dat_o(rdata),

      .overflow_o(overflow_o),
      .underrun_o(underrun_o),

      .SCK_pin(SCK_pin),
      .SSEL(SSEL),
      .MOSI(MOSI),
      .MISO(MISO)
  );


  // -- Simulation Only -- //

`ifdef __icarus

  reg [31:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_XFER: dbg_state = "XFER";
      ST_FILL: dbg_state = "FILL";
      default: dbg_state = "XXXX";
    endcase
  end

`endif


endmodule  // spi_target
