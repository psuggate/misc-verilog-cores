`timescale 1ns / 100ps
module hex_dump
#( parameter UNICODE = 1,
   parameter BLOCK_SRAM = 1
) (
   input         clock,
   input         reset,

   input         start_dump_i,
   output        is_dumping_o,
   output [10:0] fifo_level_o,

   input         s_tvalid,
   output        s_tready,
   input         s_tlast,
   input         s_tkeep,
   input [7:0]   s_tdata,

   output        m_tvalid,
   input         m_tready,
   output        m_tlast,
   output        m_tkeep,
   output [7:0]  m_tdata
   );

  localparam ABITS = BLOCK_SRAM ? 11 : 4;
  localparam ASB = ABITS - 1;

  reg tstart, tcycle, tready, fvalid, plast;
  reg [3:0] state;
  reg [7:0] tbyte0, tbyte1, tbyte2, tbyte3, wspace;
  wire flast, fready;
  wire [3:0] snext;
  wire [7:0] fdata, tbyte0_w, tbyte1_w;
  wire [ASB:0] level_w;


  assign is_dumping_o = tcycle;
  assign fifo_level_o = BLOCK_SRAM ? level_w : {7'b0, level_w};

  assign s_tready = tready;
  assign m_tkeep  = m_tvalid;

  // Nibble-to-(ASCII-)hex conversion
  assign tbyte0_w = (s_tdata[3:0] < 4'd10 ? 8'd48 : 8'd65) + s_tdata[3:0];
  assign tbyte1_w = (s_tdata[7:4] < 4'd10 ? 8'd48 : 8'd65) + s_tdata[7:4];

  // When producing Unicode strings, each character is 16-bit, and the first
  // byte is '0x00'.
  assign snext = state + (UNICODE ? 4'd2 : 4'd1);

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
      tstart <= 1'b0;
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
          if (s_tvalid && start_dump_i) begin
            // Start conversion to hex
            tstart <= 1'b1;
            tcycle <= 1'b1;
            tready <= 1'b1;
            state  <= 4'h1;
          end else begin
            tstart <= 1'b0;
            tcycle <= 1'b0;
            tready <= 1'b0;
          end
        end
        4'h1: begin
          // Capture the least-significant byte (first byte, but will be dumped
          // second)
          tstart <= 1'b0;
          fvalid <= 1'b0;
          if (s_tvalid && s_tkeep && tready) begin
            tready <= 1'b1;
            state  <= 4'h2;
            tbyte0 <= tbyte0_w;
            tbyte1 <= tbyte1_w;
          end
        end
        4'h2: begin
          // Capture the most-significant byte (but dumped first)
          fvalid <= 1'b0;
          plast  <= s_tvalid && s_tlast && tready;
          if (s_tvalid && s_tkeep && tready) begin
            tready <= 1'b0;
            state  <= snext;
            tbyte2 <= tbyte0_w;
            tbyte3 <= tbyte1_w;
            wspace <= s_tlast ? "\n" : " ";
          end
        end
        4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9, 4'ha, 4'hb: begin
          // Hex-convert & serialise the two input bytes
          fvalid <= 1'b1;
          if (fvalid && fready) begin
            state  <= snext;
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
          if (!m_tvalid) begin
            state  <= 4'h0;
          end
        end
      endcase
    end
  end


  // Output buffer
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


endmodule // hex_dump
