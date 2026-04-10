`timescale 1ns / 100ps
/**
 * Generates AXI(4) requests in response to commands from the USB interface.
 * The `axi_*` outputs are to be fed into async. FIFOs, and data is handled
 * external to this module.
 */
module axi_framer #(
    parameter FIFO_DEPTH = 512,
    localparam FBITS = $clog2(FIFO_DEPTH),
    localparam FSB = FBITS - 1,
    localparam DATA_WIDTH = 32,
    localparam MSB = DATA_WIDTH - 1,
    localparam STROBES = DATA_WIDTH / 8,
    localparam SSB = STROBES - 1,
    localparam ADDRESS_WIDTH = 32,
    localparam AZERO = {ADDRESS_WIDTH{1'b0}},
    localparam ASB = ADDRESS_WIDTH - 1
) (  // USB bus (command) clock-domain
    input cmd_clk,
    input cmd_rst,

    // Decoded command (APB, or AXI)
    input cmd_vld_i,
    input cmd_dir_i,
    output cmd_rdy_o,
    input [15:0] cmd_len_i,
    input [3:0] cmd_lun_i,
    input [27:0] cmd_adr_i,

     input fifo_ready_i,
     input [FSB:0] fifo_rd_level_i,
     input [FSB:0] fifo_wr_level_i,
     input next_frame_i,
     output next_valid_o,
     output next_ready_o,

     output axi_vld_o,
     output axi_dir_o,
     input axi_ack_i,
     input axi_fin_i,
     output [7:0] axi_len_o,
     output [SSB:0] axi_stb_o,
     output [ASB:0] axi_adr_o
     );

  localparam ST_IDLE = 1, ST_BUSY = 2, ST_READ = 4, ST_WRIT = 8, ST_LAST = 16, ST_RESP = 32, ST_DONE = 64;

  reg ready_q, valid_q;

  integer state, bytes;
  reg rdy_q;

  reg vld_q, dir_q;
  reg [7:0] bst_q;
  reg [3:0] dqs_q;
  reg [31:0] adr_q;

  assign cmd_rdy_o = rdy_q;

  assign next_valid_o = valid_q;
  assign next_ready_o = ready_q;

  assign axi_vld_o = vld_q;
  assign axi_dir_o = dir_q;
  assign axi_len_o = bst_q;
  assign axi_stb_o = dqs_q;
  assign axi_adr_o = adr_q;

  //
  // Todo:
  //
  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      rdy_q <= 1'b0;
    end
    else begin
      rdy_q <= state == ST_IDLE && fifo_rd_level_i == 0; // && fifo_wr_level_i == 0;
    end
  end

  /**
   * Transaction-framing logic, for AXI requests.
   */
  reg lst_q;
  reg [14:0] len_q;
  // wire bdy_w, pag_w;

  // Compute the number of 32-bit AXI transfers, for (len-1) bytes, and with the
  // address alignment of the request.
  wire [14:0] len_w = 14'd1 + cmd_len_i[15:2] + ((cmd_len_i[1:0] + cmd_adr_i[1:0]) > 3'd3);

  wire [31:0] adr_w = {cmd_lun_i, cmd_adr_i};
  wire [32:0] adr_end_w = adr_w + cmd_len_i;
  wire [22:0] pag_num_w = adr_end_w[32:10] - adr_w[31:10];
  wire [6:0] pag_w = 7'd1 + pag_num_w[16:10];
  reg [6:0] pag_q;

  // Todo: depends on address and burst-length.
  wire [3:0] dqs_w = 4'b1111 << cmd_adr_i[1:0];
  // wire [3:0] dqe_w = 4'b1111 >> (cmd_len_i[1:0] + 3 - cmd_adr_i[1:0])[1:0];
  reg [3:0] dqe_r, dqe_q;

  // Byte-select strobes for the final (end) transfer "beat."
  always @(cmd_adr_i[1:0], cmd_len_i[1:0]) begin
    case ({cmd_adr_i[1:0], cmd_len_i[1:0]})
      4'b00_00: dqe_r = 4'b0001;
      4'b00_01: dqe_r = 4'b0011;
      4'b00_10: dqe_r = 4'b0111;
      4'b00_11: dqe_r = 4'b1111;
      4'b01_00: dqe_r = 4'b0011;
      4'b01_01: dqe_r = 4'b0111;
      4'b01_10: dqe_r = 4'b1111;
      4'b01_11: dqe_r = 4'b0001;
      4'b10_00: dqe_r = 4'b0111;
      4'b10_01: dqe_r = 4'b1111;
      4'b10_10: dqe_r = 4'b0001;
      4'b10_11: dqe_r = 4'b0011;
      4'b11_00: dqe_r = 4'b1111;
      4'b11_01: dqe_r = 4'b0001;
      4'b11_10: dqe_r = 4'b0011;
      4'b11_11: dqe_r = 4'b0111;
    endcase
  end

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      vld_q <= 1'b0;
      lst_q <= 1'bx;
      len_q <= 'bx;
      dqs_q <= 'bx;
      dqe_q <= 'bx;
      bytes <= 'bx;
    end
    else begin
      case (state)
        ST_IDLE: begin
          vld_q <= 1'b0;
          lst_q <= 1'bx;
          len_q <= len_w;
          dqs_q <= dqs_w;
          dqe_q <= dqe_r;
          adr_q <= {cmd_lun_i, cmd_adr_i};
          bytes <= cmd_len_i + 1;
          pag_q <= ~cmd_adr_i[11:0] + 1;
          if (vld_q) begin
            state <= ST_BUSY;
          end
        end

        // Compute the size of the first burst-transaction.
        ST_BUSY: begin
          vld_q <= ~dir_q;
          if (len_q == 1) begin
            // Only one beat, so adjust strobes-mask.
            dqe_q <= dqe_q & dqs_q;
            lst_q <= 1'b1;
            bst_q <= 8'd0;
            len_q <= 15'd0;
          end
          else begin
            lst_q <= 1'b0; // Todo
            len_q <= len_w > 255 ? len_w[7:0] - 256 : 0;
            bst_q <= len_w > 255 ? 255 : len_w[7:0] - 1;
          end
          state <= dir_q ? ST_WRIT : ST_READ;
        end

        ST_READ: begin
          state <= ST_LAST;
        end

        ST_WRIT: begin
          state <= ST_LAST;
        end

        ST_LAST: begin
          state <= ST_RESP;
        end

        ST_RESP: begin
          state <= ST_DONE;
        end

        default: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end

`ifdef __potato
  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE: begin
          lst_q <= cmd_len_i == 16'd1; // Todo
        end
        default: break;
      endcase
    end
  end

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      state <= ST_IDLE;
      dir_q <= 1'bx;
    end else begin
      case (state)
        ST_IDLE: begin
          state <= state;
          //
          // Todo:
          //  - break large bursts into USB frame-sized chunks;
          //  - split bursts that cross 4kB page-boundaries;
          //  - support for unaligned addresses;
          //
          dir_q <= cmd_dir_i;
        end
        ST_READ: begin
          state <= state;
        end
        ST_WRIT: begin
          state <= state;
          lst_q <= bdy_w || pag_w;
        end
        ST_RESP: state <= state;
      endcase
    end
  end
`endif /* __potato */


`ifdef __icarus
  //
  //  Simulation Only
  ///
  reg [39:0] dbg_state;

  always @* begin
    case (state)
      ST_IDLE: dbg_state = "IDLE";
      ST_BUSY: dbg_state = "BUSY";
      ST_READ: dbg_state = "READ";
      ST_WRIT: dbg_state = "WRIT";
      ST_LAST: dbg_state = "LAST";
      ST_RESP: dbg_state = "RESP";
      ST_DONE: dbg_state = "DONE";
      default: dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule /* axi_framer */
