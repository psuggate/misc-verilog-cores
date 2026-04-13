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

  localparam ST_IDLE = 1, ST_RECV = 2, ST_WRIT = 4, ST_READ = 8, ST_SEND = 16, ST_DONE = 32;

  reg ready_q, valid_q;

  integer state, bytes;
  reg rdy_q;

  reg vld_q, dir_q;
  reg [ 7:0] bst_q;
  reg [ 3:0] dqs_q;
  reg [31:0] adr_q;

  assign cmd_rdy_o = rdy_q;

  assign next_valid_o = valid_q;
  assign next_ready_o = ready_q;

  assign axi_vld_o = vld_q;
  assign axi_dir_o = dir_q;
  assign axi_len_o = bst_q;
  assign axi_stb_o = dqs_q;
  assign axi_adr_o = adr_q;

  // Compute the number of 32-bit AXI transfers, for (len-1) bytes, and with the
  // address alignment of the request.
  wire [14:0] len_w = 14'd1 + cmd_len_i[15:2] + ((cmd_len_i[1:0] + cmd_adr_i[1:0]) > 3'd3);
  wire [31:0] adr_w = {cmd_lun_i, cmd_adr_i};

  /**
   * Address and burst-size calculation logic, for AXI write requests, and USB
   * Bulk In transactions.
   */
  reg [ASB:0] byt_adr_q, end_adr_q;
  reg [9:0] byt_num_q;

  always @(posedge cmd_clk) begin
    case (state)
      ST_IDLE:
      if (cmd_vld_i) begin
        byt_adr_q <= adr_w;
        end_adr_q <= adr_w + cmd_len_i + 1;
      end

      ST_WRIT: begin
        // When AXI transaction completes, update `byt_adr_q`
        byt_adr_q <= byt_adr_q + byt_num_q;
      end

      ST_SEND: begin
        // When Bulk In transaction completes, update `byt_adr_q`
        byt_adr_q <= byt_adr_q + byt_num_q;
      end
    endcase
  end

  // Todo: depends on address and burst-length.
  wire [3:0] dqs_w = 4'b1111 << cmd_adr_i[1:0];
  // wire [3:0] dqe_w = 4'b1111 >> (cmd_len_i[1:0] + 3 - cmd_adr_i[1:0])[1:0];
  reg [3:0] dqe_r, dqe_q;

  // Byte-select strobes for the final (end) transfer "beat."
  always @(cmd_adr_i[1:0], cmd_len_i[1:0]) begin
    case ({
      cmd_adr_i[1:0], cmd_len_i[1:0]
    })
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

`ifdef __spanner_montana
  //
  // Todo:
  //
  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      rdy_q <= 1'b0;
    end else begin
      rdy_q <= state == ST_IDLE && fifo_rd_level_i == 0;  // && fifo_wr_level_i == 0;
    end
  end
`endif  /* __spanner_montana */

  /**
   * Transaction-framing logic, for AXI requests.
   */
  reg lst_q;
  reg [14:0] len_q;
  // wire bdy_w, pag_w;

  wire [32:0] adr_end_w = adr_w + cmd_len_i;
  wire [22:0] pag_num_w = adr_end_w[32:10] - adr_w[31:10];
  wire [6:0] pag_w = 7'd1 + pag_num_w[16:10];
  reg [6:0] pag_q;

  wire [10:0] write_bytes_available_w = fifo_wr_level_i;
  wire [11:0] bytes_to_page_boundary_w = 4096 - byt_adr_q[11:0];
  wire [15:0] write_bytes_remaining_w = end_adr_q - byt_adr_q;

  always @(posedge cmd_clk) begin
    if (cmd_rst) begin
      vld_q <= 1'b0;
      rdy_q <= 1'b0;
      lst_q <= 1'bx;
      len_q <= 'bx;
      dqs_q <= 'bx;
      dqe_q <= 'bx;
      bytes <= 'bx;
    end else begin
      case (state)
        ST_IDLE: begin
          rdy_q <= 1'b0;
          if (!cmd_vld_i) begin
            vld_q <= 1'b0;
            lst_q <= 1'b0;
            state <= state;
          end else begin
            $display("%10t: Command received: WR = %d, ADR = 0x%x", $time, cmd_dir_i, cmd_adr_i);
            vld_q <= 1'b1;
            // rdy_q <= 1'b1;
            state <= cmd_dir_i ? ST_RECV : ST_READ;
          end

          dir_q <= cmd_dir_i;
          len_q <= len_w;
          dqs_q <= dqs_w;
          dqe_q <= dqe_r;
          adr_q <= {cmd_lun_i, cmd_adr_i};
          bytes <= cmd_len_i + 1;
          pag_q <= ~cmd_adr_i[11:0] + 1;
        end

        // Compute the size of the first burst-transaction.
        ST_RECV: begin
          // vld_q <= ~dir_q;
          $display("%10t: Bytes = %d, Strobes = 0x%x / 0x%x", $time, len_q, dqs_q, dqe_q);
          if (len_q == 1) begin
            // Only one beat, so adjust strobes-mask.
            dqe_q <= dqe_q & dqs_q;
            lst_q <= 1'b1;
            bst_q <= 8'd0;
            len_q <= 15'd0;
          end else if (fifo_wr_level_i >= write_bytes_remaining_w) begin
            // Send some data to AXI
            byt_num_q <= write_bytes_remaining_w;
            state <= ST_WRIT;
          end else if (fifo_wr_level_i >= BURST_BYTES) begin
            // Send some data to AXI
            byt_num_q <= BURST_BYTES;
            state <= ST_WRIT;
          end else if (fifo_wr_level_i >= bytes_to_page_boundary_w) begin
            // Send some data to AXI
            byt_num_q <= bytes_to_page_boundary_w;
            state <= ST_WRIT;
          end
          /*
          else begin
            lst_q <= 1'b0; // Todo
            len_q <= len_w > 255 ? len_w[7:0] - 256 : 0;
            bst_q <= len_w > 255 ? 255 : len_w[7:0] - 1;
          end
           */
        end

        ST_WRIT: begin
          if (byt_num_q > 0) begin
            byt_num_q <= byt_num_q - 1;
          end else begin
            state <= ST_DONE;
          end
        end

        ST_READ: begin
          state <= ST_SEND;
        end

        ST_SEND: begin
          state <= ST_DONE;
        end

        ST_DONE: begin
          state <= cmd_vld_i ? ST_DONE : ST_IDLE;
        end

        default: begin
          state <= ST_IDLE;
          #10 if (state != ST_IDLE) $fatal;
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
          lst_q <= cmd_len_i == 16'd1;  // Todo
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

  packet_fifo #(
      .WIDTH (WIDTH),
      .DEPTH (DEPTH),
      .OUTREG(OUTREG)
  ) packet_fifo_inst (
      .clock(clock),
      .reset(reset),

      .drop_i(pw_drop),
      .save_i(1'b0),
      .redo_i(1'b0),
      .next_i(1'b0),

      .s_tvalid(pw_valid),
      .s_tready(pw_ready),
      .s_tlast (pw_last),
      .s_tkeep (pw_valid),
      .s_tdata (wr_data),

      .m_tvalid(pr_valid),
      .m_tlast (pr_last),
      .m_tready(ww_ready),
      .m_tdata (pr_data)
  );

  sync_fifo #(
      .WIDTH (WIDTH),
      .ABITS (ABITS),
      .OUTREG(OUTREG)
  ) U_WRFIFO1 (
      .clock(cmd_clk),
      .reset(cmd_rst),

      .level_o(wr_level),

      .valid_i(wr_valid),
      .ready_o(wr_ready),
      .data_i (wr_data),

      .valid_o(rd_valid),
      .ready_i(ww_ready),
      .data_o (rd_data)
  );

  sync_fifo #(
      .WIDTH (WIDTH),
      .ABITS (ABITS),
      .OUTREG(OUTREG)
  ) U_RDFIFO1 (
      .clock(cmd_clk),
      .reset(cmd_rst),

      .level_o(rd_level),

      .valid_i(wr_valid),
      .ready_o(wr_ready),
      .data_i (wr_data),

      .valid_o(rd_valid),
      .ready_i(ww_ready),
      .data_o (rd_data)
  );
`endif  /* __potato */


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
      default: dbg_state = " ?? ";
    endcase
  end

`endif  /* __icarus */

endmodule  /* axi_framer */
