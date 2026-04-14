`timescale 1ns / 100ps
/**
 * Generates AXI(4) requests in response to commands from the USB interface.
 * The `axi_*` outputs are to be fed into async. FIFOs, and data is handled
 * external to this module.
 */
module cmd_to_axi_framer #(
    parameter FIFO_DEPTH = 512,
    localparam FBITS = $clog2(FIFO_DEPTH),
    localparam FSB = FBITS - 2,
    localparam DATA_WIDTH = 32,
    localparam MSB = DATA_WIDTH - 1,
    localparam STROBES = DATA_WIDTH / 8,
    localparam SSB = STROBES - 1,
    parameter USB_DWORDS = 128,
    parameter BURST_BEATS = 256,
    localparam BURST_BYTES = 1 << (BBITS + $clog2(STROBES)),
    localparam BBITS = $clog2(BURST_BEATS),
    localparam BSB = BURST_BEATS - 1,
    localparam ADDRESS_WIDTH = 32,
    localparam AZERO = {ADDRESS_WIDTH{1'b0}},
    localparam ASB = ADDRESS_WIDTH - 1
) (  // USB bus (command) clock-domain
    input cmd_clk,
    input cmd_rst,

    // Decoded command (APB, or AXI)
    input cmd_vld_i,
    input cmd_dir_i,
    input cmd_ack_i,
    output cmd_rdy_o,
    output cmd_err_o,
    input [15:0] cmd_len_i,
    input [3:0] cmd_lun_i,
    input [27:0] cmd_adr_i,

    input [FBITS:0] fifo_rd_level_i,
    input [FBITS:0] fifo_wr_level_i,

    output usb_recv_o,
    output usb_send_o,
    input  usb_sent_i,

    output axi_vld_o,
    output axi_dir_o,
    input axi_ack_i,
    input axi_fin_i,
    output [7:0] axi_len_o,
    output [SSB:0] axi_stb_o,
    output [ASB:0] axi_adr_o
);

  localparam ST_IDLE = 1, ST_RECV = 2, ST_WRIT = 4, ST_READ = 8, ST_SEND = 16, ST_DONE = 32, ST_FAIL = 64;
  integer state;
  reg [10:0] beat_num_q;
  wire cmd_err_w, beat_err_w;
  wire wr_ready_w, rd_ready_w;
  wire [10:0] beat_num_w, beat_nxt_w;

  reg cmd_rdy_q, axi_vld_q;
  reg [ 7:0] axi_len_q;
  reg [31:0] axi_adr_q;
  wire [7:0] axi_len_w, len_nxt_w;
  wire [31:0] adr_nxt_w;
  wire [FSB:0] wr_level_w, rd_level_w;

  assign cmd_rdy_o  = cmd_rdy_q;
  assign cmd_err_o  = state == ST_FAIL;

  assign usb_recv_o = state == ST_RECV;
  assign usb_send_o = state == ST_SEND;

  assign axi_vld_o  = axi_vld_q;
  assign axi_dir_o  = state == ST_RECV;
  assign axi_len_o  = axi_len_q;
  assign axi_stb_o  = 4'hf;
  assign axi_adr_o  = axi_adr_q;

  // Compute the total number of AXI transaction beats.
  assign beat_num_w = cmd_len_i[11:2] + 1;
  assign beat_err_w = cmd_len_i[15:12] != 4'd0;
  assign beat_nxt_w = beat_num_q - axi_len_q - 1;

  assign axi_len_w  = beat_num_w < BURST_BEATS ? (beat_num_w[7:0] - 1) : BURST_BEATS;
  assign len_nxt_w  = beat_nxt_w < BURST_BEATS ? (beat_nxt_w[7:0] - 1) : BURST_BEATS;
  assign adr_nxt_w  = axi_adr_q + axi_len_q + 1;

  assign wr_level_w = fifo_wr_level_i[FBITS:2];
  assign rd_level_w = fifo_rd_level_i[FBITS:2];
  assign wr_ready_w = wr_level_w >= beat_num_q || wr_level_w >= BURST_BEATS;
  assign rd_ready_w = rd_level_w >= beat_num_q || rd_level_w >= USB_DWORDS;

  /**
   * Data transfer counting and address calculation.
   */
  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      beat_num_q <= 'bx;
      axi_len_q  <= 'bx;
      axi_adr_q  <= 'bx;
    end else begin
      case (state)
        ST_IDLE: begin
          beat_num_q <= beat_num_w;
          axi_len_q  <= axi_len_w;
          axi_adr_q  <= cmd_adr_i;
        end

        ST_RECV:
        if (wr_ready_w) begin
          beat_num_q <= beat_nxt_w;
          axi_len_q  <= len_nxt_w;
          axi_adr_q  <= adr_nxt_w;
        end

        ST_SEND:
        if (rd_ready_w) begin
          beat_num_q <= beat_nxt_w;
          axi_len_q  <= len_nxt_w;
          axi_adr_q  <= adr_nxt_w;
        end

        default: begin
          beat_num_q <= beat_num_q;
          axi_len_q  <= axi_len_q;
          axi_adr_q  <= axi_adr_q;
        end
      endcase
    end
  end

  /**
   * AXI command issuing logic.
   */
  always @(posedge cmd_clk) begin
    if (cmd_rst || axi_ack_i || axi_fin_i) begin
      axi_vld_q <= 1'b0;
    end else begin
      case (state)
        ST_RECV: axi_vld_q <= wr_ready_w;
        ST_READ: axi_vld_q <= rd_ready_w;
        default: axi_vld_q <= 1'b0;
      endcase
    end
  end

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      cmd_rdy_q <= 1'b0;
    end else begin
      case (state)
        ST_WRIT: cmd_rdy_q <= beat_num_q == 0 && axi_fin_i;
        ST_SEND: cmd_rdy_q <= beat_num_q == 0 && usb_sent_i;
        default: cmd_rdy_q <= 1'b0;
      endcase
    end
  end

  // -- Main AXI-Framing State Machine -- //

  // Todo: throw errors when crossing 4kB page-boundaries, also.
  assign cmd_err_w = cmd_adr_i[1:0] != 2'b00 || cmd_len_i[1:0] != 2'b11 || beat_err_w;

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE:
        if (!cmd_vld_i) begin
          state <= state;
        end else if (cmd_err_w) begin
          $error("%10t: Invalid command", $time);
          state <= ST_FAIL;
        end else begin
          $display("%10t: Command received: RD = %d, ADR = 0x%x", $time, cmd_dir_i, cmd_adr_i);
          state <= cmd_dir_i ? ST_READ : ST_RECV;
        end

        // Compute the size of the first burst-transaction.
        ST_RECV:
        if (wr_ready_w) begin
          $display("%10t: Burst beats = %d", $time, fifo_wr_level_i[FBITS:2]);
          state <= ST_WRIT;
        end

        ST_WRIT:
        if (axi_fin_i) begin
          state <= beat_num_q > 0 ? ST_RECV : ST_DONE;
        end

        ST_READ:
        if (rd_ready_w) begin
          $display("%10t: USB transfer size = %d", $time, {fifo_rd_level_i, 2'b00});
          state <= ST_SEND;
        end

        ST_SEND:
        if (usb_sent_i) begin
          state <= beat_num_q > 0 ? ST_READ : ST_DONE;
        end

        // Wait for parent module to issue a success response.
        ST_DONE:
        if (cmd_ack_i) begin
          state <= ST_IDLE;
        end

        // Wait for parent module to issue an error response.
        ST_FAIL:
        if (cmd_ack_i) begin
          state <= ST_IDLE;
        end

        default: begin
          state <= ST_IDLE;
          #10 if (state != ST_IDLE) $fatal;
        end
      endcase
    end
  end


`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_RECV: dbg_state = "RECV";
      ST_WRIT: dbg_state = "WRIT";
      ST_READ: dbg_state = "READ";
      ST_SEND: dbg_state = "SEND";
      ST_DONE: dbg_state = "DONE";
      ST_FAIL: dbg_state = "FAIL";
      default: dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule  /* cmd_to_axi_framer */
