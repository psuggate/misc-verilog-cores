`timescale 1ns / 100ps
module hex_dump
#( parameter BYTES = 2
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


  reg tstart, tcycle, tready, fvalid, flast;
  reg [3:0] tindex;
  reg [7:0] tbyte0, tbyte1, tbyte2, tbyte3, wspace;
  wire fready;
  wire [7:0] fdata, tbyte0_w, tbyte1_w;


  assign is_dumping_o = tcycle;

  assign s_tready = tready;
  assign m_tkeep  = m_tvalid;

  assign tbyte0_w = (s_tdata[3:0] < 4'd10 ? 8'd48 : 8'd65) + s_tdata[3:0];
  assign tbyte1_w = (s_tdata[7:4] < 4'd10 ? 8'd48 : 8'd65) + s_tdata[7:4];
  assign fdata = tindex == 4'h3 ? 8'd0 :
                 tindex == 4'h4 ? tbyte3 :
                 tindex == 4'h5 ? 8'd0 :
                 tindex == 4'h6 ? tbyte2 :
                 tindex == 4'h7 ? 8'd0 :
                 tindex == 4'h8 ? tbyte1 :
                 tindex == 4'h9 ? 8'd0 :
                 tindex == 4'ha ? tbyte0 :
                 tindex == 4'hb ? 8'd0 :
                 tindex == 4'hc ? wspace :
                 "-";


  // -- FSM for Converting Bytes to Unicode Hex -- //

  always @(posedge clock) begin
    if (reset) begin
      tstart <= 1'b0;
      tcycle <= 1'b0;
      tready <= 1'b0;
      tindex <= 4'h0;
      fvalid <= 1'b0;
      flast  <= 1'b0;
    end else begin
      case (tindex)
        4'h0: begin
          fvalid <= 1'b0;
          flast  <= 1'b0;
          if (s_tvalid && start_dump_i) begin
            tstart <= 1'b1;
            tcycle <= 1'b1;
            tready <= 1'b1;
            tindex <= 4'h1;
          end else begin
            tstart <= 1'b0;
            tcycle <= 1'b0;
            tready <= 1'b0;
          end
        end
        4'h1: begin
          tstart <= 1'b0;
          fvalid <= 1'b0;
          if (s_tvalid && s_tkeep && tready) begin
            tready <= 1'b1;
            tindex <= 4'h2;
            tbyte0 <= tbyte0_w;
            tbyte1 <= tbyte1_w;
          end
        end
        4'h2: begin
          fvalid <= 1'b0;
          flast  <= s_tvalid && s_tlast && tready;
          if (s_tvalid && s_tkeep && tready) begin
            tready <= 1'b0;
            tindex <= 4'h3;
            tbyte2 <= tbyte0_w;
            tbyte3 <= tbyte1_w;
            wspace <= tlast ? "\n" : " ";
          end
        end
        4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9, 4'ha, 4'hb: begin
          fvalid <= 1'b1;
          if (fvalid && fready) begin
            tindex <= tindex + 4'h1;
          end
        end
        4'hc: begin
          // Decide whether there are more bytes, or if the packet has been
          // completed
          if (fvalid && fready) begin
            tready <= ~flast;
            tindex <= flast ? 4'hd : 4'h1;
            fvalid <= 1'b0;
          end else begin
            fvalid <= 1'b1;
          end
        end
        4'hd: begin
          // Wait for the packet to be sent
          tcycle <= 1'b0;
          if (!m_tvalid) begin
            tindex <= 4'h0;
          end
        end
      endcase
    end
  end


  // Output buffer
  // todo: does not need to be this large ??
  sync_fifo #(
      .WIDTH (9),
      .ABITS (11),
      .OUTREG(3)
  ) U_UART_FIFO1 (
      .clock(clock),
      .reset(reset),

      .level_o(fifo_level_o),

      .valid_i(fvalid),
      .ready_o(fready),
      .data_i ({tindex == 4'hc && flast, fdata}),

      .valid_o(m_tvalid),
      .ready_i(m_tready),
      .data_o ({m_tlast, m_tdata})
  );


endmodule // hex_dump
