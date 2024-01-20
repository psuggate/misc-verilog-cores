`timescale 1ns / 100ps
module hex_dump #(
    parameter UNICODE = 1,
    parameter BLOCK_SRAM = 1,
    parameter DODGY_FIFO = 0
) (
    input clock,
    input reset,

    input         start_dump_i,
    output        is_dumping_o,
    output [10:0] fifo_level_o,

    input        s_tvalid,
    output       s_tready,
    input        s_tlast,
    input        s_tkeep,
    input  [7:0] s_tdata,

    output       m_tvalid,
    input        m_tready,
    output       m_tlast,
    output       m_tkeep,
    output [7:0] m_tdata
);

  localparam ABITS = BLOCK_SRAM ? 11 : 4;
  localparam ASB = ABITS - 1;

  reg tcycle, tready, fvalid, plast, dash_q;
  reg [3:0] state;
  reg [7:0] tbyte0, tbyte1, tbyte2, tbyte3, wspace;
  wire flast, fready;
  wire [3:0] snext;
  wire [7:0] fdata, tbyte0_w, tbyte1_w;
  wire [ASB:0] level_w;


  assign is_dumping_o = tcycle;
  assign fifo_level_o = BLOCK_SRAM ? level_w : {7'b0, level_w};

  assign s_tready = tready;
  assign m_tkeep = m_tvalid;

  // Nibble-to-(ASCII-)hex conversion
  assign tbyte0_w = (s_tdata[3:0] < 4'd10 ? 8'd48 : 8'd55) + s_tdata[3:0];
  assign tbyte1_w = (s_tdata[7:4] < 4'd10 ? 8'd48 : 8'd55) + s_tdata[7:4];

  // When producing Unicode strings, each character is 16-bit, and the first
  // byte is '0x00'.
  assign snext = state + (UNICODE ? 4'd1 : 4'd2);

  assign flast = state == 4'hc && plast;
  assign fdata = state == 4'h3 ? 8'd0 :
                 state == 4'h4 ? tbyte3 :
                 state == 4'h5 ? 8'd0 :
                 state == 4'h6 ? tbyte2 :
                 state == 4'h7 ? 8'd0 :
                 state == 4'h8 ? tbyte1 :
                 state == 4'h9 ? 8'd0 :
                 state == 4'ha ? tbyte0 :
                 state == 4'hb ? 8'd0 :
                 state == 4'hc ? wspace :
                 "-";


  // -- FSM for Converting Bytes to Unicode Hex -- //

  always @(posedge clock) begin
    if (reset) begin
      tcycle <= 1'b0;
      tready <= 1'b0;
      state  <= 4'h0;
      fvalid <= 1'b0;
      plast  <= 1'b0;
    end else begin
      case (state)
        4'h0: begin
          fvalid <= 1'b0;
          plast  <= 1'b0;
          dash_q <= 1'b1;
          if (s_tvalid && start_dump_i) begin
            // Start conversion to hex
            tcycle <= 1'b1;
            tready <= 1'b1;
            state  <= 4'h1;
          end else begin
            tcycle <= 1'b0;
            tready <= 1'b0;
          end
        end
        4'h1: begin
          // Capture the least-significant byte (first byte, but will be dumped
          // second)
          fvalid <= 1'b0;
          if (s_tvalid && s_tkeep && tready) begin
            tready <= 1'b1;
            state  <= s_tlast ? 4'h3 : 4'h2;
            tbyte0 <= tbyte0_w;
            tbyte1 <= tbyte1_w;
            if (s_tlast) begin
              tbyte2 <= "x";
              tbyte3 <= "x";
              plast  <= 1'b1;
            end
          end
        end
        4'h2: begin
          // Capture the most-significant byte (but dumped first)
          if (s_tvalid && tready) begin
            tready <= 1'b0;
            fvalid <= 1'b1;
            state  <= snext;
            if (s_tkeep) begin
              tbyte2 <= tbyte0_w;
              tbyte3 <= tbyte1_w;
            end else begin
              tbyte2 <= "x";
              tbyte3 <= "x";
            end
            plast  <= s_tlast | plast;
            wspace <= s_tlast ? "\n" : dash_q ? "-" : " ";
            dash_q <= ~dash_q;
          end else begin
            fvalid <= 1'b0;
            tready <= 1'b1;
          end
        end
        4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9, 4'ha, 4'hb: begin
          // Hex-convert & serialise the two input bytes
          fvalid <= 1'b1;
          if (fvalid && fready) begin
            state <= snext;
          end
        end
        4'hc: begin
          // Decide whether there are more bytes, or if the packet has been
          // completed
          if (fvalid && fready) begin
            tready <= ~plast;
            state  <= plast ? 4'hd : 4'h1;
            fvalid <= 1'b0;
          end else begin
            fvalid <= 1'b1;
          end
        end
        4'hd: begin
          // Wait for the packet to be sent
          tcycle <= 1'b0;
          if (!level_w[ASB]) begin
            state <= 4'h0;
          end
        end
      endcase
    end
  end


  // -- Output Buffer -- //

  generate
    if (DODGY_FIFO) begin : g_sync_fifo

  // todo: should be optional (or, external) ...
  sync_fifo #(
      .WIDTH (9),
      .ABITS (ABITS),
      .OUTREG(BLOCK_SRAM ? 3 : 0)
  ) U_UART_FIFO1 (
      .clock(clock),
      .reset(reset),

      .level_o(level_w),

      .valid_i(fvalid),
      .ready_o(fready),
      .data_i ({flast, fdata}),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .data_o ({m_tlast, m_tdata})
  );

    end else begin : g_axis_fifo

      axis_fifo #(
          .DEPTH(BLOCK_SRAM ? 2048 : 16),
          .DATA_WIDTH(8),
          .KEEP_ENABLE(0),
          .KEEP_WIDTH(1),
          .LAST_ENABLE(1),
          .ID_ENABLE(0),
          .ID_WIDTH(1),
          .DEST_ENABLE(0),
          .DEST_WIDTH(1),
          .USER_ENABLE(0),
          .USER_WIDTH(1),
          .RAM_PIPELINE(1),
          .OUTPUT_FIFO_ENABLE(0),
          .FRAME_FIFO(0),
          .USER_BAD_FRAME_VALUE(0),
          .USER_BAD_FRAME_MASK(0),
          .DROP_BAD_FRAME(0),
          .DROP_WHEN_FULL(0)
      ) U_BULK_FIFO0 (
          .clk(clock),
          .rst(reset),

          // AXI input
          .s_axis_tdata(fdata),
          .s_axis_tkeep(1'b1),
          .s_axis_tvalid(fvalid),
          .s_axis_tready(fready),
          .s_axis_tlast(flast),
          .s_axis_tid(1'b0),
          .s_axis_tdest(1'b0),
          .s_axis_tuser(1'b0),

          .pause_req(1'b0),

          // AXI output
          .m_axis_tdata(m_tdata),
          .m_axis_tkeep(),
          .m_axis_tvalid(m_tvalid),
          .m_axis_tready(m_tready),
          .m_axis_tlast(m_tlast),
          .m_axis_tid(),
          .m_axis_tdest(),
          .m_axis_tuser(),
          // Status
          .status_depth(level_w),
          .status_overflow(),
          .status_bad_frame(),
          .status_good_frame()
      );

    end
  endgenerate


endmodule  // hex_dump
